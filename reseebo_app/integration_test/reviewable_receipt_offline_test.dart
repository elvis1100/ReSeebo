import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:reseebo_app/core/adapters/i_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/adapters/sqlite_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/services/ocr_engine_registry.dart';
import 'package:reseebo_app/core/services/receipt_suggestion_service.dart';

// One immutable APK executes one phase per real process. Hot restart, adapter
// reopen and rereading a snapshot are deliberately not restart evidence.
final _processToken = '$pid-${DateTime.now().microsecondsSinceEpoch}';
const _directoryName = 'reviewable-receipt-acceptance';

Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final registry = await OcrEngineRegistry.loadBundled();
  final descriptors = registry.descriptors;
  await registry.close();

  for (final engine in descriptors.where((engine) => !engine.available)) {
    debugPrint('DEFERRED ${engine.label}: ${engine.unavailableReason}');
    testWidgets(
      '${engine.label} device acceptance DEFERRED: ${engine.unavailableReason}',
      (tester) async {},
      skip: true,
    );
  }

  testWidgets('real offline pending, confirmation and correction lifecycle', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, _directoryName));
    await root.create(recursive: true);
    final marker = File(p.join(root.path, 'lifecycle.json'));
    final previous = await marker.exists()
        ? jsonDecode(await marker.readAsString()) as Map<String, dynamic>
        : <String, dynamic>{'nextPhase': 'seed'};
    final phase = previous['nextPhase'] as String;
    expect(phase, isIn(['seed', 'review', 'verify']));
    if (phase != 'seed') {
      expect(previous['processToken'], isNot(_processToken));
      expect(
        previous['pid'],
        isNot(pid),
        reason: 'A new native process is required.',
      );
    }
    final available = descriptors.where((engine) => engine.available).toList();
    expect(available.map((engine) => engine.id), contains(OcrEngineId.mlKit));
    if (phase != 'seed') {
      expect(
        available.map((engine) => engine.id.wireId).toList(),
        previous['engines'],
        reason: 'All phases must use the same immutable APK and engine set.',
      );
    }
    for (final engine in available) {
      final engineRoot = Directory(p.join(root.path, engine.id.wireId));
      await engineRoot.create(recursive: true);
      final adapter = await SqliteReseeboDataAdapter.open(
        databasePath: p.join(engineRoot.path, 'acceptance.sqlite'),
        mediaDirectory: Directory(p.join(engineRoot.path, 'owned')),
      );
      try {
        switch (phase) {
          case 'seed':
            await _seed(adapter, engineRoot, engine);
          case 'review':
            await _review(adapter, engineRoot, engine);
          case 'verify':
            await _verify(adapter, engineRoot, engine);
        }
      } finally {
        await adapter.close();
      }
    }
    final result = <String, dynamic>{
      'phase': phase,
      'nextPhase': phase == 'seed'
          ? 'review'
          : phase == 'review'
          ? 'verify'
          : 'complete',
      'processToken': _processToken,
      'pid': pid,
      'engines': available.map((engine) => engine.id.wireId).toList(),
      'deferredEngines': descriptors
          .where((engine) => !engine.available)
          .map(
            (engine) => {
              'engine': engine.id.wireId,
              'reason': engine.unavailableReason,
            },
          )
          .toList(),
    };
    // Written only after every available engine completed this phase. A failure
    // never advances the lifecycle or removes retained SQLite/media evidence.
    await marker.writeAsString(jsonEncode(result), flush: true);
    binding.reportData = result;
    debugPrint('REVIEWABLE_ACCEPTANCE ${jsonEncode(result)}');
  });
}

Future<void> _seed(
  SqliteReseeboDataAdapter adapter,
  Directory root,
  OcrEngineDescriptor engine,
) async {
  expect(await adapter.getRecentReceipts(), isEmpty);
  expect(await adapter.getLedgerEntries(), isEmpty);
  expect((await adapter.getProducts()).length, greaterThanOrEqualTo(150));
  final source = Directory(p.join(root.path, 'fixture-inputs'));
  await source.create();
  // Reuses Task 1's local image/arial48 fixture technique. These controlled
  // images prove native plumbing and durable evidence, not shop-photo accuracy.
  final originals = <String>[];
  final recognition = <String>[];
  final comparisons = <String>[];
  final originalHashes = <String>[];
  for (var page = 0; page < 2; page++) {
    final rows = page == 0
        ? ['SUPPLIER A', 'OCTOBER 8, 2026', '2 PC COFFEE ORIGINAL 26G 168.00']
        : ['SUPPLIER A', '2 PC SOAP WHITE 60G 200.00', 'TOTAL 368.00'];
    final bytes = _receiptPixels(rows);
    originalHashes.add(sha256.convert(bytes).toString());
    for (final (label, paths) in [
      ('original', originals),
      ('recognition', recognition),
      ('comparison', comparisons),
    ]) {
      final file = File(p.join(source.path, '$label-$page.png'));
      await file.writeAsBytes(bytes, flush: true);
      paths.add(file.path);
    }
  }
  Future<ReceiptDraft> recognize() => adapter.processReceiptImages(
    originals,
    recognitionImagePaths: recognition,
    comparisonImagePaths: comparisons,
    engineId: engine.id,
    preprocessingRevision: 'acceptance-identity-v1',
  );
  final cold = await recognize();
  final warm = await recognize();
  _identity(cold, engine);
  _identity(warm, engine);
  expect(cold.ocrPages, hasLength(2));
  expect(
    cold.ocrPages.first.textLines.map((line) => line.text).join(' '),
    contains('COFFEE'),
  );
  expect(
    cold.ocrPages.last.textLines.map((line) => line.text).join(' '),
    contains('SOAP'),
  );
  expect(cold.lines, hasLength(2));
  expect(cold.lines.map((line) => line.sourcePage), [0, 1]);
  expect(cold.lines.map((line) => line.extractedAmountCents), [16800, 20000]);
  final suggested = ReceiptSuggestionService().suggest(
    cold,
    products: await adapter.getProducts(),
    confirmedHistory: const [],
    importedAt: DateTime(2026, 10, 10),
  );
  expect(suggested.rawText, cold.rawText);
  expect(
    suggested.lines.first.provenance[ReceiptSuggestionField.amount]?.origin,
    ReceiptFieldOrigin.extracted,
  );
  final pending = await adapter.savePendingReceipt(
    suggested,
    operationId: 'seed-read',
  );
  final retry = await adapter.savePendingReceipt(
    suggested,
    operationId: 'seed-read',
  );
  expect(retry.id, pending.id);
  expect(retry.alreadySaved, isTrue);
  final stored = (await adapter.getPendingReceipt(pending.id)).draft;
  expect(stored.rawText, cold.rawText);
  final blank = File(p.join(source.path, 'unreadable.png'));
  await blank.writeAsBytes(_receiptPixels(const []), flush: true);
  try {
    final unreadable = await adapter.processReceiptImage(
      blank.path,
      engineId: engine.id,
    );
    expect(unreadable.lines, isEmpty);
    expect(unreadable.rawText.trim(), isEmpty);
  } on AppException {
    // ML Kit exposes empty text as a typed failure. Either representation must
    // still allow saving the original through the photos-only boundary.
  }
  final photosOnly = await adapter.savePendingReceipt(
    ReceiptDraft(imagePath: blank.path),
    operationId: 'seed-photos-only',
  );
  final blankStored = (await adapter.getPendingReceipt(photosOnly.id)).draft;
  expect(blankStored.rawText, isEmpty);
  expect(blankStored.ocrRun, isNull);
  final ledger = await adapter.getLedgerEntries();
  expect(ledger, hasLength(2));
  expect(
    ledger.every((entry) => entry.status == LedgerEntryStatus.needsReview),
    isTrue,
  );
  expect(await adapter.getRecentReceipts(), isEmpty);
  final evidence = {
    'pendingId': pending.id,
    'photosOnlyId': photosOnly.id,
    'rawText': cold.rawText,
    'ocrEvidence': _ocrEvidence(cold),
    'originalHashes': originalHashes,
    'blankHash': sha256.convert(await blank.readAsBytes()).toString(),
    'coldMs': cold.ocrRun!.elapsedMs,
    'warmMs': warm.ocrRun!.elapsedMs,
  };
  await File(
    p.join(root.path, 'evidence.json'),
  ).writeAsString(jsonEncode(evidence), flush: true);
  // Deleting picker-like source files catches adapters that retained cache paths.
  await source.delete(recursive: true);
  await _media(stored, originalHashes, expectedPages: 2);
  await _media(blankStored, [
    evidence['blankHash'] as String,
  ], expectedPages: 1);
  debugPrint(
    'REVIEWABLE_ENGINE ${jsonEncode({'engine': engine.id.wireId, 'phase': 'seed', 'coldMs': evidence['coldMs'], 'warmMs': evidence['warmMs']})}',
  );
}

Future<Map<String, dynamic>> _readEvidence(Directory root) async =>
    jsonDecode(await File(p.join(root.path, 'evidence.json')).readAsString())
        as Map<String, dynamic>;

Future<void> _review(
  SqliteReseeboDataAdapter adapter,
  Directory root,
  OcrEngineDescriptor engine,
) async {
  final evidence = await _readEvidence(root);
  final pending = await adapter.getPendingReceipt(
    evidence['pendingId'] as String,
  );
  final draft = pending.draft;
  await _assertEvidence(draft, evidence, engine);
  expect(
    draft.lines.first.provenance[ReceiptSuggestionField.amount]?.origin,
    ReceiptFieldOrigin.extracted,
  );
  await expectLater(
    adapter.confirmPendingReceipt(
      pending.id,
      expectedRevision: pending.revision,
      operationId: 'invalid-confirm',
    ),
    throwsA(isA<ValidationException>()),
  );
  expect(await adapter.getRecentReceipts(), isEmpty);
  expect(
    (await adapter.getPendingReceipt(pending.id)).revision,
    pending.revision,
  );
  for (var index = 0; index < 2; index++) {
    final productId = 'acceptance-${engine.id.wireId}-$index';
    await adapter.saveProduct(
      Product(
        id: productId,
        name: index == 0 ? 'Coffee' : 'Soap',
        brand: 'Acceptance Brand',
        variant: index == 0 ? 'Original' : 'White',
        size: index == 0 ? '26g' : '60g',
      ),
    );
    draft.lines[index].productId = productId;
    _ownerLine(draft.lines[index], index == 0 ? 20000 : 30000);
  }
  draft.supplierName = 'Supplier A';
  draft.purchasedAt = DateTime(2026, 10, 8);
  draft.dateConfirmed = true;
  draft.detectedTotalCents = 50000;
  draft.provenance[ReceiptMetadataField.total] = _owner;
  final edited = await adapter.savePendingReceipt(
    draft,
    operationId: 'edit-pending',
    pendingId: pending.id,
    expectedRevision: pending.revision,
  );
  await expectLater(
    adapter.savePendingReceipt(
      draft,
      operationId: 'stale-edit',
      pendingId: pending.id,
      expectedRevision: pending.revision,
    ),
    throwsA(isA<RevisionConflictException>()),
  );
  expect(
    (await adapter.getProductComparison(draft.lines.first.productId!)).history,
    isEmpty,
  );
  final confirmed = await adapter.confirmPendingReceipt(
    edited.id,
    expectedRevision: edited.revision,
    operationId: 'confirm-read',
  );
  expect(confirmed.unitCostsCents, [10000, 15000]);
  final replay = await adapter.confirmPendingReceipt(
    edited.id,
    expectedRevision: edited.revision,
    operationId: 'confirm-read',
  );
  expect(replay.receiptId, confirmed.receiptId);
  expect(replay.alreadySaved, isTrue);
  expect(
    await adapter.resolveConfirmedReceiptId(pending.id),
    confirmed.receiptId,
  );
  final before = await adapter.getReceipt(confirmed.receiptId);
  final edit = await adapter.getConfirmedReceiptEdit(confirmed.receiptId);
  final correctionDraft = edit.draft;
  _ownerLine(correctionDraft.lines.first, 26000);
  correctionDraft.detectedTotalCents = 56000;
  final correction = await adapter.savePendingReceipt(
    correctionDraft,
    operationId: 'save-correction',
    correctionOfReceiptId: confirmed.receiptId,
    expectedConfirmedRevision: edit.revision,
  );
  expect(
    (await adapter.getProductComparison(
      draft.lines.first.productId!,
    )).latestPrices.single.purchase.costPerPieceCents,
    10000,
  );
  final corrected = await adapter.confirmPendingReceipt(
    correction.id,
    expectedRevision: correction.revision,
    operationId: 'confirm-correction',
  );
  expect(corrected.receiptId, confirmed.receiptId);
  expect(corrected.lineIds, confirmed.lineIds);
  expect(corrected.unitCostsCents, [13000, 15000]);
  final after = await adapter.getReceipt(confirmed.receiptId);
  expect(
    after.lines.map((line) => line.recordedOrder),
    before.lines.map((line) => line.recordedOrder),
  );
  expect(
    after.lines.map((line) => line.sequence),
    before.lines.map((line) => line.sequence),
  );
  expect(after.lines.first.recordedAt, before.lines.first.recordedAt);
  expect(after.receipt.imagePaths, before.receipt.imagePaths);
  expect((await adapter.getRecentReceipts()), hasLength(1));
  final blankPending = await adapter.getPendingReceipt(
    evidence['photosOnlyId'] as String,
  );
  final manual = blankPending.draft;
  await _media(manual, [evidence['blankHash'] as String], expectedPages: 1);
  manual.supplierName = 'Photos-only Supplier';
  manual.purchasedAt = DateTime(2026, 10, 9);
  manual.dateConfirmed = true;
  manual.lines.add(
    ParsedLineItem(
      description: 'Owner supplied exact product',
      quantity: 2,
      unit: PurchaseUnit.piece,
      piecesPerPack: 1,
      grossAmountCents: 12000,
      confirmed: true,
      provenance: {ReceiptSuggestionField.amount: _owner},
    ),
  );
  final filled = await adapter.savePendingReceipt(
    manual,
    operationId: 'fill-photos',
    pendingId: blankPending.id,
    expectedRevision: blankPending.revision,
  );
  final manualResult = await adapter.confirmPendingReceipt(
    filled.id,
    expectedRevision: filled.revision,
    operationId: 'confirm-photos',
  );
  expect(manualResult.unitCostsCents, [6000]);
  evidence['receiptId'] = confirmed.receiptId;
  evidence['manualReceiptId'] = manualResult.receiptId;
  await File(
    p.join(root.path, 'evidence.json'),
  ).writeAsString(jsonEncode(evidence), flush: true);
}

Future<void> _verify(
  SqliteReseeboDataAdapter adapter,
  Directory root,
  OcrEngineDescriptor engine,
) async {
  final evidence = await _readEvidence(root);
  final id = evidence['receiptId'] as String;
  final edit = await adapter.getConfirmedReceiptEdit(id);
  expect(edit.revision, 2);
  await _assertEvidence(edit.draft, evidence, engine);
  expect(edit.draft.lines.map((line) => line.grossAmountCents), [26000, 30000]);
  expect(
    edit.draft.lines.first.provenance[ReceiptSuggestionField.amount]?.origin,
    ReceiptFieldOrigin.ownerEdited,
  );
  final revisions = await adapter.getReceiptRevisions(id);
  expect(revisions, hasLength(1));
  expect(revisions.single.revision, 1);
  expect(revisions.single.draft.lines.map((line) => line.grossAmountCents), [
    20000,
    30000,
  ]);
  await _assertEvidence(revisions.single.draft, evidence, engine);
  final comparison = await adapter.getProductComparison(
    edit.draft.lines.first.productId!,
  );
  expect(
    comparison.history,
    hasLength(1),
    reason: 'Corrections must not add purchases.',
  );
  expect(comparison.latestPrices.single.purchase.costPerPieceCents, 13000);
  final active = await adapter.getReceipt(id);
  expect(active.lines, hasLength(2));
  expect(active.lines.map((line) => line.costPerPieceCents), [13000, 15000]);
  expect(
    (await adapter.getProductComparison(
      edit.draft.lines.last.productId!,
    )).history,
    hasLength(1),
  );
  final ledger = await adapter.getLedgerEntries();
  expect(ledger, hasLength(2));
  expect(
    ledger.every((entry) => entry.status == LedgerEntryStatus.confirmed),
    isTrue,
  );
  expect(
    await adapter.resolveConfirmedReceiptId(evidence['pendingId'] as String),
    id,
  );
  final manual = await adapter.getConfirmedReceiptEdit(
    evidence['manualReceiptId'] as String,
  );
  expect(manual.draft.rawText, isEmpty);
  expect(manual.draft.ocrRun, isNull);
  await _media(manual.draft, [
    evidence['blankHash'] as String,
  ], expectedPages: 1);
  expect(
    (await adapter.getReceipt(manual.receiptId)).lines.single.costPerPieceCents,
    6000,
  );
}

const _owner = ReceiptFieldProvenance(
  origin: ReceiptFieldOrigin.ownerEdited,
  explanation: 'Owner supplied this acceptance value.',
);

void _ownerLine(ParsedLineItem line, int amount) {
  line.quantity = 2;
  line.unit = PurchaseUnit.piece;
  line.piecesPerPack = 1;
  line.discountCents = 0;
  line.grossAmountCents = amount;
  line.amountEdited = true;
  line.quantityEdited = true;
  line.possibleDuplicateOf = null;
  line.confirmed = true;
  for (final field in [
    ReceiptSuggestionField.amount,
    ReceiptSuggestionField.quantity,
    ReceiptSuggestionField.unit,
    ReceiptSuggestionField.piecesPerPack,
  ]) {
    line.provenance[field] = _owner;
  }
}

List<int> _receiptPixels(List<String> rows) {
  final pixels = image.Image(width: 1600, height: 600);
  image.fill(pixels, color: image.ColorRgb8(255, 255, 255));
  for (var row = 0; row < rows.length; row++) {
    image.drawString(
      pixels,
      rows[row],
      font: image.arial48,
      x: 60,
      y: 50 + row * 150,
      color: image.ColorRgb8(0, 0, 0),
    );
  }
  return image.encodePng(pixels);
}

void _identity(ReceiptDraft draft, OcrEngineDescriptor engine) {
  expect(draft.ocrRun?.engineId, engine.id);
  expect(draft.ocrRun?.modelVersion, engine.modelVersion);
  expect(draft.ocrRun?.runtimeVersion, engine.runtimeVersion);
  expect(draft.ocrRun?.preprocessingRevision, 'acceptance-identity-v1');
}

String _ocrEvidence(ReceiptDraft draft) => jsonEncode([
  for (final page in draft.ocrPages)
    [
      for (final lines in [page.textLines, page.originalTextLines])
        [
          for (final line in lines)
            {
              'text': line.text,
              'bounds': [line.left, line.top, line.width, line.height],
              'tokens': [
                for (final token in line.tokens)
                  [
                    token.text,
                    token.left,
                    token.top,
                    token.width,
                    token.height,
                  ],
              ],
            },
        ],
    ],
]);

Future<void> _assertEvidence(
  ReceiptDraft draft,
  Map<String, dynamic> evidence,
  OcrEngineDescriptor engine,
) async {
  _identity(draft, engine);
  expect(draft.rawText, evidence['rawText']);
  expect(_ocrEvidence(draft), evidence['ocrEvidence']);
  expect(draft.lines.map((line) => line.extractedAmountCents), [16800, 20000]);
  await _media(
    draft,
    List<String>.from(evidence['originalHashes'] as List),
    expectedPages: 2,
  );
}

Future<void> _media(
  ReceiptDraft draft,
  List<String> hashes, {
  required int expectedPages,
}) async {
  expect(draft.imagePaths, hasLength(expectedPages));
  expect(draft.mediaEvidence, hasLength(expectedPages));
  for (var index = 0; index < expectedPages; index++) {
    final media = draft.mediaEvidence[index];
    expect(media.original.path, draft.imagePaths[index]);
    for (final reference in [
      media.original,
      media.recognition,
      media.comparison,
    ].whereType<ReceiptImageReference>()) {
      expect(reference.path, contains('${p.separator}owned${p.separator}'));
      expect(
        sha256.convert(await File(reference.path).readAsBytes()).toString(),
        hashes[index],
      );
      expect(reference.sha256, hashes[index]);
      expect(reference.width, 1600);
      expect(reference.height, 600);
      expect(reference.preprocessingIdentity, isNotEmpty);
    }
    if (draft.ocrRun != null) {
      expect(media.recognition, isNotNull);
      expect(media.comparison, isNotNull);
      expect(
        draft.ocrPages[index].recognitionImagePath,
        media.recognition!.path,
      );
      expect(draft.ocrPages[index].comparisonImagePath, media.comparison!.path);
      for (final line in draft.ocrPages[index].textLines) {
        expect(line.left, greaterThanOrEqualTo(0));
        expect(line.top, greaterThanOrEqualTo(0));
        expect(line.width, greaterThan(0));
        expect(line.height, greaterThan(0));
        expect(line.left + line.width, lessThanOrEqualTo(1600));
        expect(line.top + line.height, lessThanOrEqualTo(600));
      }
    }
  }
}
