import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:reseebo_app/core/adapters/i_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/adapters/sqlite_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/database/reseebo_database.dart';
import 'package:reseebo_app/core/database/pending_receipt_repository.dart';
import 'package:reseebo_app/core/services/local_file_store.dart';
import 'package:reseebo_app/core/services/ocr_service.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _NoOcr implements OcrService {
  @override
  Future<void> close() async {}
  @override
  Future<List<OcrTextLine>> recognize(String path) =>
      throw StateError('Pending save must not run OCR');
}

class _FailSecondCopy extends LocalFileStore {
  _FailSecondCopy(super.directory);
  int calls = 0;
  @override
  Future<StoredLocalFile> persist(
    String path, {
    required String category,
    String? existingPath,
  }) {
    if (++calls == 2) {
      throw const ValidationException('Injected second copy failure');
    }
    return super.persist(path, category: category, existingPath: existingPath);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root;
  late Directory media;
  late String databasePath;
  late SqliteReseeboDataAdapter adapter;
  late Database db;
  Future<SqliteReseeboDataAdapter> open() => SqliteReseeboDataAdapter.open(
    databaseFactory: databaseFactoryFfi,
    databasePath: databasePath,
    mediaDirectory: media,
    ocrService: _NoOcr(),
    starterProducts: const [],
    clock: () => DateTime.utc(2026, 10, 10),
  );
  Future<String> photo(String name, [int red = 1]) async {
    final pixels = image.Image(width: 3, height: 7)
      ..setPixelRgb(0, 0, red, 2, 3);
    final file = File(p.join(root.path, '$name.png'));
    await file.writeAsBytes(image.encodePng(pixels));
    return file.path;
  }

  Future<ReceiptDraft> photosOnly(String name) async =>
      ReceiptDraft(operationId: 'draft-$name', imagePath: await photo(name));
  Future<int> count(String table) async =>
      (await db.rawQuery('SELECT count(*) n FROM $table')).single['n'] as int;
  Future<List<String>> owned() async =>
      (await media.list(recursive: true).toList())
          .whereType<File>()
          .map((e) => e.path)
          .toList()
        ..sort();
  Future<SaveReceiptResult> confirmed(
    String name, {
    String number = '',
  }) async => adapter.saveConfirmedReceipt(
    ReceiptDraft(
      operationId: 'confirmed-$name',
      imagePath: await photo(name, 30),
      supplierName: 'Supplier A',
      supplierBranch: 'Main',
      purchasedAt: DateTime(2026, 10, 9),
      dateConfirmed: true,
      receiptNumber: number,
      lines: [
        ParsedLineItem(
          id: 'line-$name',
          description: 'Coffee 26g',
          quantity: 1,
          unit: PurchaseUnit.piece,
          piecesPerPack: 1,
          grossAmountCents: 2100,
          confirmed: true,
        ),
      ],
    ),
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('reseebo-pending-');
    media = Directory(p.join(root.path, 'owned'));
    databasePath = p.join(root.path, 'records.sqlite');
    adapter = await open();
    db = await databaseFactoryFfi.openDatabase(databasePath);
  });
  tearDown(() async {
    await adapter.close();
    await root.delete(recursive: true);
  });

  test('save_failed_scan_and_reopen', () async {
    final draft = await photosOnly('failed');
    draft.warnings.add('OCR failed');
    final result = await adapter.savePendingReceipt(
      draft,
      operationId: 'save-failed',
    );
    await adapter.close();
    await File(draft.imagePath).delete();
    adapter = await open();
    db = await databaseFactoryFfi.openDatabase(databasePath);
    final pending = await adapter.getPendingReceipt(result.id);
    expect(pending.revision, 1);
    expect(pending.draft.lines, isEmpty);
    expect(pending.draft.warnings, ['OCR failed']);
    final ref = pending.draft.mediaEvidence.single.original;
    expect(ref.width, 3);
    expect(ref.height, 7);
    expect(ref.sha256.length, 64);
    expect(ref.path, pending.draft.imagePath);
    expect(await File(ref.path).exists(), isTrue);
    expect(
      (await adapter.getLedgerEntries()).single.status,
      LedgerEntryStatus.needsReview,
    );
    expect(await adapter.getRecentReceipts(), isEmpty);
  });
  test('pending_estimates_do_not_create_history', () async {
    final draft = await photosOnly('estimate');
    draft.supplierName = 'Unknown store';
    draft.lines.add(
      ParsedLineItem(description: 'Estimated item', grossAmountCents: 4500),
    );
    draft.detectedTotalCents = 4500;
    draft.totalIsPartial = true;
    final result = await adapter.savePendingReceipt(
      draft,
      operationId: 'estimate',
    );
    expect(
      (await adapter.getPendingReceipt(result.id)).draft.detectedTotalCents,
      4500,
    );
    for (final table in [
      'receipts',
      'purchase_lines',
      'products',
      'suppliers',
      'product_aliases',
      'supplier_product_aliases',
    ]) {
      expect(await count(table), 0, reason: table);
    }
  });
  test(
    'same_operation_retries_once including owned paths and deleted picker',
    () async {
      final draft = await photosOnly('retry');
      final first = await adapter.savePendingReceipt(
        draft,
        operationId: 'retry',
      );
      final persisted = (await adapter.getPendingReceipt(first.id)).draft;
      await File(draft.imagePath).delete();
      for (final retry in [draft, persisted]) {
        final result = await adapter.savePendingReceipt(
          retry,
          operationId: 'retry',
        );
        expect(result.id, first.id);
        expect(result.revision, 1);
        expect(result.alreadySaved, isTrue);
      }
      expect(await count('pending_receipts'), 1);
      expect(await count('receipt_write_operations'), 1);
      expect((await owned()).length, 1);
    },
  );
  test('changed_payload_reusing_operation_is_rejected', () async {
    final draft = await photosOnly('retry-change');
    await adapter.savePendingReceipt(draft, operationId: 'retry');
    draft.notes = 'changed';
    await expectLater(
      adapter.savePendingReceipt(draft, operationId: 'retry'),
      throwsA(isA<ValidationException>()),
    );
    expect(await count('pending_receipts'), 1);
  });
  test('changed image bytes reusing operation are rejected', () async {
    final draft = await photosOnly('image-change');
    await adapter.savePendingReceipt(draft, operationId: 'image-change');
    await photo('image-change', 3);
    await expectLater(
      adapter.savePendingReceipt(draft, operationId: 'image-change'),
      throwsA(isA<ValidationException>()),
    );
  });
  test(
    'stale_revision_keeps_current_data before reading missing media',
    () async {
      final original = await photosOnly('revision');
      final first = await adapter.savePendingReceipt(
        original,
        operationId: 'initial',
      );
      final draft = (await adapter.getPendingReceipt(first.id)).draft
        ..notes = 'second';
      final second = await adapter.savePendingReceipt(
        draft,
        operationId: 'update',
        pendingId: first.id,
        expectedRevision: 1,
      );
      expect(second.revision, 2);
      final stale = ReceiptDraft(imagePath: p.join(root.path, 'missing.png'));
      await expectLater(
        adapter.savePendingReceipt(
          stale,
          operationId: 'stale',
          pendingId: first.id,
          expectedRevision: 1,
        ),
        throwsA(isA<RevisionConflictException>()),
      );
      expect((await adapter.getPendingReceipt(first.id)).draft.notes, 'second');
    },
  );
  test(
    'update needs revision and insert rejects unexpected revision',
    () async {
      final draft = await photosOnly('contract');
      await expectLater(
        adapter.savePendingReceipt(
          draft,
          operationId: 'bad-insert',
          expectedRevision: 1,
        ),
        throwsA(isA<ValidationException>()),
      );
      final first = await adapter.savePendingReceipt(
        draft,
        operationId: 'initial',
      );
      await expectLater(
        adapter.savePendingReceipt(
          draft,
          operationId: 'bad-update',
          pendingId: first.id,
        ),
        throwsA(isA<RevisionConflictException>()),
      );
    },
  );
  test(
    'all media roles persist and paths and OCR coordinate evidence align',
    () async {
      final original = await photo('original');
      final recognition = await photo('recognition', 2);
      final comparison = await photo('comparison', 3);
      final draft = ReceiptDraft(
        imagePath: original,
        recognitionImagePath: recognition,
        ocrPages: [
          ReceiptOcrPage(
            imagePath: original,
            recognitionImagePath: recognition,
            comparisonImagePath: comparison,
            textLines: [const OcrTextLine(text: 'selected', left: 50)],
            originalTextLines: [const OcrTextLine(text: 'original', left: 5)],
          ),
        ],
      );
      final saved = await adapter.savePendingReceipt(
        draft,
        operationId: 'roles',
      );
      final restored = (await adapter.getPendingReceipt(saved.id)).draft;
      for (final path in [original, recognition, comparison]) {
        await File(path).delete();
      }
      final page = restored.mediaEvidence.single;
      expect(restored.ocrPages.single.imagePath, page.original.path);
      expect(restored.recognitionImagePath, page.recognition!.path);
      expect(
        restored.ocrPages.single.comparisonImagePath,
        page.comparison!.path,
      );
      expect(restored.ocrPages.single.textLines.single.left, 50);
      expect(restored.ocrPages.single.originalTextLines.single.left, 5);
      for (final ref in [page.original, page.recognition!, page.comparison!]) {
        expect(await File(ref.path).exists(), isTrue);
      }
      expect((await owned()).length, 3);
    },
  );
  test('failed_media_copy_cleans_only_new_files', () async {
    final first = await adapter.savePendingReceipt(
      await photosOnly('prior'),
      operationId: 'prior',
    );
    final before = await owned();
    final original = await photo('new-original', 5);
    final recognition = await photo('new-recognition', 6);
    final repository = PendingReceiptRepository(
      db,
      _FailSecondCopy(media),
      clock: () => DateTime.utc(2026),
    );
    await expectLater(
      repository.savePendingReceipt(
        ReceiptDraft(imagePath: original, recognitionImagePath: recognition),
        operationId: 'failed-copy',
      ),
      throwsA(isA<ValidationException>()),
    );
    expect(await owned(), before);
    expect(await count('pending_receipts'), 1);
    expect(await count('receipt_write_operations'), 1);
    expect(
      await File(
        (await adapter.getPendingReceipt(first.id)).draft.imagePath,
      ).exists(),
      isTrue,
    );
    expect(await File(original).exists(), isTrue);
  });
  test(
    'database abort atomically retains prior row and operation with only new files cleaned',
    () async {
      final first = await adapter.savePendingReceipt(
        await photosOnly('prior'),
        operationId: 'prior',
      );
      final before = await owned();
      await db.execute(
        "CREATE TRIGGER fail_operation BEFORE INSERT ON receipt_write_operations BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      final replacement = (await photosOnly('replacement'))
        ..notes = 'must not commit';
      await expectLater(
        adapter.savePendingReceipt(
          replacement,
          operationId: 'fail',
          pendingId: first.id,
          expectedRevision: 1,
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect((await adapter.getPendingReceipt(first.id)).revision, 1);
      expect(await owned(), before);
      expect(await count('receipt_write_operations'), 1);
    },
  );
  test('duplicate original pages and malformed media never commit', () async {
    final draft = await photosOnly('same');
    await expectLater(
      adapter.savePendingReceipt(
        ReceiptDraft(
          imagePath: draft.imagePath,
          imagePaths: [draft.imagePath, draft.imagePath],
        ),
        operationId: 'same',
      ),
      throwsA(isA<ValidationException>()),
    );
    final text = File(p.join(root.path, 'fake.png'))
      ..writeAsStringSync('not an encoded image');
    await expectLater(
      adapter.savePendingReceipt(
        ReceiptDraft(imagePath: text.path),
        operationId: 'fake',
      ),
      throwsA(isA<ValidationException>()),
    );
    expect(await count('pending_receipts'), 0);
    expect(await owned(), isEmpty);
  });
  test(
    'duplicates include pending and confirmed raw target IDs with owner override',
    () async {
      final draft = await photosOnly('duplicate');
      final first = await adapter.savePendingReceipt(
        draft,
        operationId: 'first',
      );
      await expectLater(
        adapter.savePendingReceipt(draft, operationId: 'second'),
        throwsA(
          isA<DuplicateReceiptException>().having((e) => e.receiptIds, 'ids', [
            first.id,
          ]),
        ),
      );
      draft.allowDuplicate = true;
      await adapter.savePendingReceipt(draft, operationId: 'override');
      final saved = await confirmed('confirmed');
      final detail = await adapter.getReceipt(saved.receiptId);
      await expectLater(
        adapter.savePendingReceipt(
          ReceiptDraft(imagePath: detail.receipt.imagePath),
          operationId: 'against-confirmed',
        ),
        throwsA(
          isA<DuplicateReceiptException>().having(
            (e) => e.receiptIds,
            'ids',
            contains(saved.receiptId),
          ),
        ),
      );
    },
  );
  test(
    'receipt number duplicate requires known supplier name and same branch',
    () async {
      final saved = await confirmed('number', number: 'OR1');
      final draft = (await photosOnly('different'))
        ..supplierName = 'Supplier A'
        ..supplierBranch = 'Main'
        ..receiptNumber = 'or1';
      await expectLater(
        adapter.savePendingReceipt(draft, operationId: 'number'),
        throwsA(
          isA<DuplicateReceiptException>().having((e) => e.receiptIds, 'ids', [
            saved.receiptId,
          ]),
        ),
      );
      draft.supplierBranch = 'Other';
      await adapter.savePendingReceipt(draft, operationId: 'branch');
      final unknown = (await photosOnly('unknown'))..receiptNumber = 'OR1';
      await photo('unknown', 2);
      await adapter.savePendingReceipt(unknown, operationId: 'unknown');
      expect(await count('suppliers'), 1);
    },
  );
  test(
    'correction links one ledger entry excludes source duplicate and keeps history',
    () async {
      final source = await confirmed('correction');
      final receipt = (await adapter.getReceipt(source.receiptId)).receipt;
      final draft = ReceiptDraft(
        imagePath: receipt.imagePath,
        supplierName: receipt.supplierName,
      );
      final correction = await adapter.savePendingReceipt(
        draft,
        operationId: 'correction',
        correctionOfReceiptId: source.receiptId,
        expectedConfirmedRevision: 1,
      );
      final ledger = await adapter.getLedgerEntries();
      expect(ledger.length, 1);
      expect(ledger.single.id, source.receiptId);
      expect(ledger.single.pendingId, correction.id);
      expect(ledger.single.confirmedReceiptId, source.receiptId);
      expect(ledger.single.status, LedgerEntryStatus.needsReview);
      expect((await adapter.getRecentReceipts()).length, 1);
      expect(await count('purchase_lines'), 1);
      final restored = await adapter.getPendingReceipt(correction.id);
      expect(restored.correctionOfReceiptId, source.receiptId);
      expect(restored.baseConfirmedRevision, 1);
      await expectLater(
        adapter.savePendingReceipt(
          draft,
          operationId: 'stale-confirmed',
          correctionOfReceiptId: source.receiptId,
          expectedConfirmedRevision: 2,
        ),
        throwsA(isA<RevisionConflictException>()),
      );
    },
  );
  test(
    'ledger search is literal, limit consistent and stable ties use IDs',
    () async {
      for (var n = 1; n <= 3; n++) {
        final draft = (await photosOnly('search-$n'))
          ..supplierName = 'Store $n'
          ..rawText = 'raw needle $n';
        await photo('search-$n', n);
        await adapter.savePendingReceipt(draft, operationId: 'search-$n');
      }
      expect((await adapter.getLedgerEntries(query: 'needle')).length, 3);
      expect(await adapter.getLedgerEntries(query: '%'), isEmpty);
      final all = await adapter.getLedgerEntries();
      final ids = all.map((e) => e.id).toList();
      expect(ids, [...ids]..sort());
      expect(
        (await adapter.getLedgerEntries(limit: 2)).map((e) => e.id),
        ids.take(2),
      );
      await expectLater(
        adapter.getLedgerEntries(limit: 0),
        throwsA(isA<ValidationException>()),
      );
    },
  );
  test(
    'migrate_v7_retains_confirmed_data and foreign key constraints',
    () async {
      final saved = await confirmed('migration');
      final before = await adapter.getReceipt(saved.receiptId);
      for (final table in [
        'pending_receipt_images',
        'ledger_entry_links',
        'receipt_revisions',
        'receipt_evidence',
        'receipt_write_operations',
        'pending_receipts',
      ]) {
        await db.execute('DROP TABLE $table');
      }
      await db.setVersion(7);
      await adapter.close();
      adapter = await open();
      db = await databaseFactoryFfi.openDatabase(databasePath);
      expect(await db.getVersion(), 8);
      expect(ReseeboDatabase.version, 8);
      expect(
        (await adapter.getReceipt(saved.receiptId)).receipt.imagePath,
        before.receipt.imagePath,
      );
      expect(await count('purchase_lines'), 1);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await expectLater(
        db.insert('pending_receipt_images', {
          'pending_id': 'absent',
          'page_index': 0,
          'image_path': 'x',
          'image_hash': 'x',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.insert('receipt_images', {
          'receipt_id': 'pending-only',
          'page_index': 0,
          'image_path': 'x',
          'image_hash': 'x',
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
  test('pending snapshot is private before queued writes await', () async {
    final draft = await photosOnly('private');
    final saving = adapter.savePendingReceipt(draft, operationId: 'private');
    draft.notes = 'mutated';
    draft.lines.add(ParsedLineItem(description: 'later'));
    final result = await saving;
    final pending = await adapter.getPendingReceipt(result.id);
    expect(pending.draft.notes, '');
    expect(pending.draft.lines, isEmpty);
    final edited = pending.draft..notes = 'private edit';
    expect(edited.notes, 'private edit');
    expect(pending.draft.notes, '');
  });
  test(
    'old evidence remains readable after replacement and failed owned reuse',
    () async {
      final first = await adapter.savePendingReceipt(
        await photosOnly('old'),
        operationId: 'old',
      );
      final old = (await adapter.getPendingReceipt(first.id)).draft;
      final replacement = await photosOnly('new');
      await photo('new', 5);
      await adapter.savePendingReceipt(
        replacement,
        operationId: 'new',
        pendingId: first.id,
        expectedRevision: 1,
      );
      expect(await File(old.imagePath).exists(), isTrue);
      final current = (await adapter.getPendingReceipt(first.id)).draft;
      final before = await owned();
      await db.execute(
        "CREATE TRIGGER fail_owned BEFORE INSERT ON receipt_write_operations BEGIN SELECT RAISE(ABORT, 'owned failure'); END",
      );
      await expectLater(
        adapter.savePendingReceipt(
          current,
          operationId: 'owned-fail',
          pendingId: first.id,
          expectedRevision: 2,
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await owned(), before);
      expect(await File(current.imagePath).exists(), isTrue);
    },
  );
  test(
    'late pending retry survives removal and retained stable link',
    () async {
      final draft = await photosOnly('late');
      final first = await adapter.savePendingReceipt(
        draft,
        operationId: 'late',
      );
      final source = await confirmed('stable-target');
      await db.insert('ledger_entry_links', {
        'pending_id': first.id,
        'confirmed_receipt_id': source.receiptId,
        'created_at': 1,
      });
      await db.delete(
        'pending_receipts',
        where: 'id = ?',
        whereArgs: [first.id],
      );
      await File(draft.imagePath).delete();
      final retry = await adapter.savePendingReceipt(
        draft,
        operationId: 'late',
      );
      expect(retry.id, first.id);
      expect(retry.alreadySaved, isTrue);
      expect(
        (await db.query('ledger_entry_links')).single['confirmed_receipt_id'],
        source.receiptId,
      );
      expect(await count('pending_receipts'), 0);
      expect(await count('pending_receipt_images'), 0);
    },
  );
  test(
    'boundary rejects mismatched page evidence and too many lines before copying',
    () async {
      final path = await photo('boundary');
      await expectLater(
        adapter.savePendingReceipt(
          ReceiptDraft(
            imagePath: path,
            ocrPages: [
              const ReceiptOcrPage(imagePath: 'different', textLines: []),
            ],
          ),
          operationId: 'mismatch',
        ),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        adapter.savePendingReceipt(
          ReceiptDraft(
            imagePath: path,
            lines: List.generate(1001, (i) => ParsedLineItem(id: '$i')),
          ),
          operationId: 'too-many',
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(await owned(), isEmpty);
    },
  );
  test(
    'same receipt number also checks pending rows with known supplier evidence',
    () async {
      final firstDraft = (await photosOnly('number-one'))
        ..supplierName = 'Known'
        ..supplierBranch = 'Main'
        ..receiptNumber = 'or9';
      final first = await adapter.savePendingReceipt(
        firstDraft,
        operationId: 'number-one',
      );
      final next = (await photosOnly('number-two'))
        ..supplierName = 'known'
        ..supplierBranch = 'main'
        ..receiptNumber = 'OR9';
      await photo('number-two', 2);
      await expectLater(
        adapter.savePendingReceipt(next, operationId: 'number-two'),
        throwsA(
          isA<DuplicateReceiptException>().having((e) => e.receiptIds, 'ids', [
            first.id,
          ]),
        ),
      );
    },
  );
  test(
    'mock pending edit and retry keeps confirmed catalog and feed private',
    () async {
      final mock = MockReseeboDataAdapter();
      final products = (await mock.getProducts()).length;
      final suppliers = (await mock.getSuppliers()).length;
      final confirmedCount = (await mock.getRecentReceipts()).length;
      final draft = ReceiptDraft(
        operationId: 'mock',
        imagePath: 'mock-original',
        notes: 'needle',
        lines: [ParsedLineItem(id: 'mock-line', description: 'unknown')],
      );
      final first = await mock.savePendingReceipt(
        draft,
        operationId: 'mock-save',
      );
      expect(
        (await mock.savePendingReceipt(
          draft,
          operationId: 'mock-save',
        )).alreadySaved,
        isTrue,
      );
      draft.notes = 'changed';
      await expectLater(
        mock.savePendingReceipt(draft, operationId: 'mock-save'),
        throwsA(isA<ValidationException>()),
      );
      final loaded = await mock.getPendingReceipt(first.id);
      expect(loaded.draft.notes, 'needle');
      expect(
        (await mock.getLedgerEntries(query: 'needle')).single.pendingId,
        first.id,
      );
      expect((await mock.getRecentReceipts()).length, confirmedCount);
      expect((await mock.getProducts()).length, products);
      expect((await mock.getSuppliers()).length, suppliers);
      final edit = loaded.draft..notes = 'edited';
      expect(
        (await mock.savePendingReceipt(
          edit,
          operationId: 'mock-edit',
          pendingId: first.id,
          expectedRevision: 1,
        )).revision,
        2,
      );
      await expectLater(
        mock.savePendingReceipt(
          edit,
          operationId: 'mock-stale',
          pendingId: first.id,
          expectedRevision: 1,
        ),
        throwsA(isA<RevisionConflictException>()),
      );
    },
  );
  test(
    'media hash and pixel dimensions are verified at storage boundary',
    () async {
      final path = await photo('hash-check');
      final digest = sha256.convert(await File(path).readAsBytes()).toString();
      for (final reference in [
        ReceiptImageReference(
          path: path,
          sha256: 'incorrect',
          width: 3,
          height: 7,
          preprocessingIdentity: 'rotate',
        ),
        ReceiptImageReference(
          path: path,
          sha256: digest,
          width: 7,
          height: 3,
          preprocessingIdentity: 'rotate',
        ),
      ]) {
        await expectLater(
          adapter.savePendingReceipt(
            ReceiptDraft(
              imagePath: path,
              mediaEvidence: [ReceiptPageMedia(original: reference)],
            ),
            operationId: 'bad-evidence-${reference.sha256}',
          ),
          throwsA(isA<ValidationException>()),
        );
      }
      expect(await count('pending_receipts'), 0);
      expect(await owned(), isEmpty);
    },
  );
  test(
    'command changes under used operation ID reject after pending update',
    () async {
      final draft = await photosOnly('command');
      final initial = await adapter.savePendingReceipt(
        draft,
        operationId: 'command',
      );
      final edit = (await adapter.getPendingReceipt(initial.id)).draft
        ..notes = 'edited';
      await adapter.savePendingReceipt(
        edit,
        operationId: 'command-edit',
        pendingId: initial.id,
        expectedRevision: 1,
      );
      await File(draft.imagePath).delete();
      final initialRetry = await adapter.savePendingReceipt(
        draft,
        operationId: 'command',
      );
      expect(initialRetry.revision, 1);
      expect(initialRetry.alreadySaved, isTrue);
      await expectLater(
        adapter.savePendingReceipt(
          draft,
          operationId: 'command',
          pendingId: initial.id,
          expectedRevision: 2,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect((await adapter.getPendingReceipt(initial.id)).revision, 2);
    },
  );
  test(
    'an update reuses identical content and role rather than recopying picker files',
    () async {
      final draft = await photosOnly('reuse-picker');
      final initial = await adapter.savePendingReceipt(
        draft,
        operationId: 'reuse-initial',
      );
      final before = await owned();
      draft.notes = 'edit only';
      await adapter.savePendingReceipt(
        draft,
        operationId: 'reuse-edit',
        pendingId: initial.id,
        expectedRevision: 1,
      );
      expect(await owned(), before);
    },
  );
  test(
    'direct confirmed save reviews a prior pending duplicate without creating history',
    () async {
      final original = await photo('pending-then-confirmed');
      final saved = await adapter.savePendingReceipt(
        ReceiptDraft(imagePath: original),
        operationId: 'prior-pending',
      );
      final draft = ReceiptDraft(
        imagePath: original,
        supplierName: 'Supplier A',
        dateConfirmed: true,
        purchasedAt: DateTime(2026, 10, 9),
        lines: [
          ParsedLineItem(
            description: 'Coffee',
            quantity: 1,
            unit: PurchaseUnit.piece,
            piecesPerPack: 1,
            grossAmountCents: 100,
            confirmed: true,
          ),
        ],
      );
      await expectLater(
        adapter.saveConfirmedReceipt(draft),
        throwsA(
          isA<DuplicateReceiptException>().having(
            (e) => e.receiptIds,
            'pending duplicate',
            [saved.id],
          ),
        ),
      );
      expect(await count('receipts'), 0);
      expect(await count('suppliers'), 0);
      expect(await count('products'), 0);
    },
  );
}
