import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reseebo_app/core/adapters/sqlite_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/adapters/i_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/services/ocr_service.dart';
import 'package:reseebo_app/core/database/migrations/migration_001_initial.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeOcr implements OcrService {
  String? lastImagePath;
  @override
  Future<List<OcrTextLine>> recognize(String imagePath) async {
    lastImagePath = imagePath;
    return [
      const OcrTextLine(text: 'Supplier A'),
      const OcrTextLine(text: '2026-10-08'),
      const OcrTextLine(text: '2 COF ORIG 26G 168.00'),
      const OcrTextLine(text: 'TOTAL 168.00'),
    ];
  }

  @override
  Future<void> close() async {}
}

const coffee = Product(
  id: 'coffee',
  name: 'Coffee',
  brand: 'Brand X',
  variant: 'Original',
  size: '26g',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root;
  late Directory media;
  late String databasePath;
  late SqliteReseeboDataAdapter adapter;
  late Database db;
  late FakeOcr ocr;

  Future<SqliteReseeboDataAdapter> openAdapter() =>
      SqliteReseeboDataAdapter.open(
        databaseFactory: databaseFactoryFfi,
        databasePath: databasePath,
        mediaDirectory: media,
        ocrService: ocr,
        clock: () => DateTime.utc(2026, 10, 9, 8),
      );

  Future<ReceiptDraft> draft({
    String operation = 'op-1',
    String supplier = 'Supplier A',
    String branch = 'Main',
    String productId = 'coffee',
    String description = 'COF ORIG 26G',
    int gross = 17600,
    int discount = 800,
    DateTime? date,
    bool hasTime = false,
    String number = '',
    String? imagePath,
    List<String>? imagePaths,
  }) async {
    final source = File(imagePath ?? p.join(root.path, '$operation.jpg'));
    if (imagePath == null) {
      await source.writeAsString('original receipt bytes for $operation');
    }
    return ReceiptDraft(
      operationId: operation,
      imagePath: source.path,
      imagePaths: imagePaths,
      supplierName: supplier,
      supplierBranch: branch,
      purchasedAt: date ?? DateTime(2026, 10, 8),
      hasPurchaseTime: hasTime,
      dateConfirmed: true,
      receiptNumber: number,
      lines: [
        ParsedLineItem(
          description: description,
          productId: productId,
          quantity: 2,
          unit: PurchaseUnit.pack,
          piecesPerPack: 10,
          grossAmountCents: gross,
          discountCents: discount,
          confirmed: true,
        ),
      ],
    );
  }

  Future<int> count(String table) async =>
      (await db.rawQuery('SELECT COUNT(*) AS n FROM $table')).single['n']
          as int;
  Future<List<File>> persistentFiles() async =>
      (await media.list(recursive: true).toList()).whereType<File>().toList();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('reseebo-sqlite-test-');
    media = Directory(p.join(root.path, 'persistent-media'));
    databasePath = p.join(root.path, 'records.sqlite');
    ocr = FakeOcr();
    adapter = await openAdapter();
    db = await databaseFactoryFfi.openDatabase(databasePath);
    await adapter.saveProduct(coffee);
  });

  tearDown(() async {
    await adapter.close();
    await root.delete(recursive: true);
  });

  test(
    'fresh local database has exactly seven versioned tables and no sample receipts',
    () async {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
      );
      expect(tables.map((row) => row['name']).toSet(), {
        'store_profiles',
        'products',
        'product_aliases',
        'suppliers',
        'receipts',
        'purchase_lines',
        'receipt_images',
      });
      expect(await db.getVersion(), 2);
      expect(
        (await db.rawQuery('PRAGMA foreign_keys')).single.values.single,
        1,
      );
      expect(await adapter.getRecentReceipts(), isEmpty);
      expect((await adapter.getStoreProfile()).defaultMarkupPercent, isNull);
    },
  );

  test(
    'all receipt pages save atomically, reopen and retain their order',
    () async {
      final input = await draft(operation: 'multi-page');
      final second = File(p.join(root.path, 'second.jpg'));
      await second.writeAsString('second original receipt page');
      final multi = await draft(
        operation: 'multi-page',
        imagePath: input.imagePath,
        imagePaths: [input.imagePath, second.path],
      );
      multi.lines.single.sourcePage = 1;
      final saved = await adapter.saveConfirmedReceipt(multi);
      final detail = await adapter.getReceipt(saved.receiptId);
      expect(detail.receipt.imagePaths, hasLength(2));
      expect(
        await File(detail.receipt.imagePaths[0]).readAsBytes(),
        await File(input.imagePath).readAsBytes(),
      );
      expect(
        await File(detail.receipt.imagePaths[1]).readAsBytes(),
        await second.readAsBytes(),
      );
      expect(detail.lines.single.imagePath, detail.receipt.imagePaths[1]);
      expect(detail.lines.single.sourcePage, 1);
      expect((await adapter.saveConfirmedReceipt(multi)).alreadySaved, isTrue);
      expect(await count('receipt_images'), 2);
      await adapter.close();
      adapter = await openAdapter();
      expect(
        (await adapter.getReceipt(saved.receiptId)).receipt.imagePaths,
        detail.receipt.imagePaths,
      );
      await second.writeAsString('changed after saving');
      await expectLater(
        adapter.saveConfirmedReceipt(multi),
        throwsA(isA<ValidationException>()),
      );
    },
  );

  test(
    'failure copying a later page cleans earlier copies and saves no rows',
    () async {
      final input = await draft(operation: 'missing-page');
      final multi = await draft(
        operation: 'missing-page',
        imagePath: input.imagePath,
        imagePaths: [input.imagePath, p.join(root.path, 'missing.jpg')],
      );
      await expectLater(
        adapter.saveConfirmedReceipt(multi),
        throwsA(isA<ValidationException>()),
      );
      expect(await count('receipts'), 0);
      expect(await count('purchase_lines'), 0);
      expect(await count('receipt_images'), 0);
      expect(await persistentFiles(), isEmpty);
      expect(await File(input.imagePath).exists(), isTrue);
    },
  );

  test(
    'identical receipt pages and unresolved overlaps cannot be saved',
    () async {
      final input = await draft(operation: 'repeat-page');
      final same = File(p.join(root.path, 'same.jpg'));
      await File(input.imagePath).copy(same.path);
      final multi = await draft(
        operation: 'repeat-page',
        imagePath: input.imagePath,
        imagePaths: [input.imagePath, same.path],
      );
      await expectLater(
        adapter.processReceiptImages(multi.imagePaths),
        throwsA(isA<ValidationException>()),
      );
      expect(ocr.lastImagePath, isNull);
      await expectLater(
        adapter.saveConfirmedReceipt(multi),
        throwsA(isA<ValidationException>()),
      );
      expect(await persistentFiles(), isEmpty);
      input.lines.single.possibleDuplicateOf = 'other-line';
      await expectLater(
        adapter.saveConfirmedReceipt(input),
        throwsA(isA<ValidationException>()),
      );
      expect(await count('receipts'), 0);
    },
  );

  test(
    'a repeated later page flags the existing receipt as a duplicate',
    () async {
      final input = await draft(operation: 'first-multi');
      final page2 = File(p.join(root.path, 'page2.jpg'));
      await page2.writeAsString('shared original second page');
      final multi = await draft(
        operation: 'first-multi',
        imagePath: input.imagePath,
        imagePaths: [input.imagePath, page2.path],
      );
      final saved = await adapter.saveConfirmedReceipt(multi);
      final repeated = await draft(
        operation: 'repeat-later',
        imagePath: page2.path,
      );
      await expectLater(
        adapter.saveConfirmedReceipt(repeated),
        throwsA(
          isA<DuplicateReceiptException>().having(
            (error) => error.receiptIds,
            'existing receipt',
            contains(saved.receiptId),
          ),
        ),
      );
      expect(await count('receipts'), 1);
      expect(await persistentFiles(), hasLength(2));
    },
  );

  test(
    'receipts cannot overwrite existing supplier notes or stale selected identity',
    () async {
      await adapter.saveSupplier(
        const Supplier(
          id: 'supplier-b',
          name: 'Supplier B',
          branch: 'Main',
          notes: 'B notes',
        ),
      );
      final input = await draft(
        operation: 'supplier-notes',
        supplier: 'Supplier B',
      );
      input.supplierNotes = 'hidden stale A notes';
      input.supplierId = 'supplier-b';
      await adapter.saveConfirmedReceipt(input);
      expect((await adapter.getSuppliers()).single.notes, 'B notes');
      final stale = await draft(
        operation: 'stale-identity',
        supplier: 'Old Name',
      );
      stale.supplierId = 'supplier-b';
      await expectLater(
        adapter.saveConfirmedReceipt(stale),
        throwsA(isA<ValidationException>()),
      );
      expect(await count('suppliers'), 1);
      expect(await count('receipts'), 1);
    },
  );

  test(
    'version 1 upgrade retains receipts, original files and purchase lines',
    () async {
      final saved = await adapter.saveConfirmedReceipt(
        await draft(operation: 'legacy-upgrade'),
      );
      final before = await adapter.getReceipt(saved.receiptId);
      final legacyPath = p.join(root.path, 'legacy.sqlite');
      final legacy = await databaseFactoryFfi.openDatabase(
        legacyPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (connection, _) async {
            for (final sql in initialSchema) {
              await connection.execute(sql);
            }
          },
        ),
      );
      for (final table in [
        'store_profiles',
        'products',
        'suppliers',
        'receipts',
        'purchase_lines',
        'product_aliases',
      ]) {
        for (final row in await db.query(table)) {
          final values = Map<String, Object?>.of(row)..remove('source_page');
          await legacy.insert(table, values);
        }
      }
      await legacy.close();
      final upgraded = await SqliteReseeboDataAdapter.open(
        databaseFactory: databaseFactoryFfi,
        databasePath: legacyPath,
        mediaDirectory: media,
        ocrService: FakeOcr(),
      );
      try {
        final after = await upgraded.getReceipt(saved.receiptId);
        expect(after.receipt.imagePaths, [before.receipt.imagePath]);
        expect(
          after.lines.single.netAmountCents,
          before.lines.single.netAmountCents,
        );
        expect(after.lines.single.sourcePage, 0);
        expect(await File(after.receipt.imagePath).exists(), isTrue);
        expect(
          (await upgraded.saveConfirmedReceipt(
            await draft(operation: 'legacy-upgrade'),
          )).alreadySaved,
          isTrue,
        );
      } finally {
        await upgraded.close();
      }
    },
  );

  test(
    'net amounts and rational costs persist with original images and aliases',
    () async {
      final input = await draft();
      final result = await adapter.saveConfirmedReceipt(input);
      expect(result.unitCostsCents.single, 840);
      final detail = await adapter.getReceipt(result.receiptId);
      expect(detail.receipt.totalCents, 16800);
      expect(detail.lines.single.netAmountCents, 16800);
      expect(detail.lines.single.discountCents, 800);
      expect(detail.lines.single.totalPieces, 20);
      expect(detail.lines.single.purchaseLabel, '2 packs × 10 pcs');
      expect(p.isWithin(media.path, detail.receipt.imagePath), isTrue);
      expect(
        await File(detail.receipt.imagePath).readAsBytes(),
        await File(input.imagePath).readAsBytes(),
      );
      expect(
        (await adapter.getAliases('coffee')).single.description,
        'COF ORIG 26G',
      );
      expect(
        (await adapter.matchAliases(' cof   orig 26g ')).single.exactAlias,
        isTrue,
      );
    },
  );

  test(
    'real SQLite abort rolls back receipt, lines, aliases and newly added supplier',
    () async {
      await db.execute(
        "CREATE TRIGGER reject_line BEFORE INSERT ON purchase_lines WHEN NEW.original_description = 'FAIL' BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
      );
      final input = await draft();
      input.lines.add(
        ParsedLineItem(
          description: 'FAIL',
          productId: 'coffee',
          quantity: 1,
          unit: PurchaseUnit.piece,
          grossAmountCents: 500,
          confirmed: true,
        ),
      );
      await expectLater(
        adapter.saveConfirmedReceipt(input),
        throwsA(isA<DatabaseException>()),
      );
      for (final table in [
        'receipts',
        'purchase_lines',
        'product_aliases',
        'suppliers',
      ]) {
        expect(await count(table), 0, reason: table);
      }
      expect(await persistentFiles(), isEmpty);
      expect(await File(input.imagePath).exists(), isTrue);
    },
  );

  test(
    'unconfirmed dates/products, invalid conversion, quantities, money and totals cannot save',
    () async {
      final changes = <void Function(ReceiptDraft)>[
        (input) => input.dateConfirmed = false,
        (input) => input.supplierName = '',
        (input) => input.lines.single.confirmed = false,
        (input) => input.lines.single.productId = null,
        (input) => input.lines.single.quantity = 0,
        (input) => input.lines.single.unit = null,
        (input) => input.lines.single.piecesPerPack = null,
        (input) => input.lines.single.grossAmountCents = 0,
        (input) => input.lines.single.discountCents = -1,
        (input) => input.lines.single.discountCents =
            input.lines.single.grossAmountCents!,
        (input) => input.detectedTotalCents = 1,
        (input) {
          input.lines.single.unit = PurchaseUnit.piece;
          input.lines.single.piecesPerPack = 10;
        },
      ];
      for (var index = 0; index < changes.length; index++) {
        final input = await draft(operation: 'invalid-$index');
        changes[index](input);
        await expectLater(
          adapter.saveConfirmedReceipt(input),
          throwsA(isA<ValidationException>()),
        );
      }
      expect(await count('receipts'), 0);
      expect(await persistentFiles(), isEmpty);
      final missingProduct = await draft(
        operation: 'missing-product',
        productId: 'not-in-catalog',
      );
      await expectLater(
        adapter.saveConfirmedReceipt(missingProduct),
        throwsA(isA<ValidationException>()),
      );
      expect(await count('suppliers'), 0);
      expect(await persistentFiles(), isEmpty);
    },
  );

  test(
    'receipt-total difference requires an explicit owner confirmation',
    () async {
      final input = await draft();
      input.detectedTotalCents = 17000;
      await expectLater(
        adapter.saveConfirmedReceipt(input),
        throwsA(isA<ValidationException>()),
      );
      input.totalDifferenceConfirmed = true;
      final result = await adapter.saveConfirmedReceipt(input);
      expect(
        (await adapter.getReceipt(result.receiptId)).receipt.totalCents,
        16800,
      );
    },
  );

  test(
    'retry and overlapping taps reuse one receipt without creating extra files',
    () async {
      final input = await draft();
      final results = await Future.wait([
        adapter.saveConfirmedReceipt(input),
        adapter.saveConfirmedReceipt(input),
      ]);
      expect(results[0].receiptId, results[1].receiptId);
      expect(results[1].alreadySaved, isTrue);
      expect(await count('receipts'), 1);
      expect(await count('purchase_lines'), 1);
      expect((await persistentFiles()).length, 1);
      await File(input.imagePath).delete();
      final retry = await adapter.saveConfirmedReceipt(input);
      expect(retry.alreadySaved, isTrue);
      input.lines.single.grossAmountCents = 18000;
      await expectLater(
        adapter.saveConfirmedReceipt(input),
        throwsA(isA<ValidationException>()),
      );
      expect(await count('receipts'), 1);
    },
  );

  test(
    'mutable review drafts are snapshotted before the save awaits',
    () async {
      final input = await draft();
      final saving = adapter.saveConfirmedReceipt(input);
      input.supplierName = 'Changed during await';
      input.lines.single.grossAmountCents = 50000;
      input.lines.single.description = 'Changed description';
      final result = await saving;
      final detail = await adapter.getReceipt(result.receiptId);
      expect(detail.receipt.supplier.name, 'Supplier A');
      expect(detail.receipt.totalCents, 16800);
      expect(detail.lines.single.originalDescription, 'COF ORIG 26G');
    },
  );

  test(
    'duplicate images require review; owner-confirmed repeats keep both purchases',
    () async {
      final first = await draft();
      final saved = await adapter.saveConfirmedReceipt(first);
      final second = await draft(operation: 'op-2', imagePath: first.imagePath);
      await expectLater(
        adapter.saveConfirmedReceipt(second),
        throwsA(
          isA<DuplicateReceiptException>().having(
            (error) => error.receiptIds,
            'prior receipt',
            [saved.receiptId],
          ),
        ),
      );
      expect(await count('receipts'), 1);
      expect((await persistentFiles()).length, 1);
      second.allowDuplicate = true;
      await adapter.saveConfirmedReceipt(second);
      expect(await count('receipts'), 2);
      expect((await adapter.getProductComparison('coffee')).history.length, 2);
    },
  );

  test(
    'receipt number duplicate review is scoped to the supplier branch',
    () async {
      await adapter.saveConfirmedReceipt(await draft(number: 'OR-123'));
      final sameBranch = await draft(operation: 'op-2', number: 'or-123');
      await expectLater(
        adapter.saveConfirmedReceipt(sameBranch),
        throwsA(isA<DuplicateReceiptException>()),
      );
      await adapter.saveConfirmedReceipt(
        await draft(
          operation: 'op-3',
          number: 'OR-123',
          branch: 'Other branch',
        ),
      );
      expect(await count('receipts'), 2);
      expect(
        (await adapter.getSuppliers()).map((supplier) => supplier.branch),
        ['Main', 'Other branch'],
      );
    },
  );

  test(
    'different products may share an alias and always remain suggestions',
    () async {
      await adapter.saveProduct(
        const Product(
          id: 'coffee-33',
          name: 'Coffee',
          brand: 'Brand X',
          variant: 'Original',
          size: '33g',
        ),
      );
      await adapter.saveConfirmedReceipt(await draft(description: 'COFFEE'));
      await adapter.saveConfirmedReceipt(
        await draft(
          operation: 'op-2',
          description: 'COFFEE',
          productId: 'coffee-33',
        ),
      );
      final suggestions = await adapter.matchAliases('Coffee');
      expect(suggestions.map((suggestion) => suggestion.product.id).toSet(), {
        'coffee',
        'coffee-33',
      });
      expect(
        suggestions.every(
          (suggestion) => suggestion.reason.contains('more than one'),
        ),
        isTrue,
      );
      final recognized = await adapter.processReceiptImage(
        (await draft(operation: 'ocr-only')).imagePath,
      );
      expect(recognized.lines.single.productId, isNull);
      expect(recognized.lines.single.confirmed, isFalse);
      final alias = (await adapter.getAliases('coffee')).single;
      await adapter.deleteAlias(alias.id);
      expect(
        (await adapter.matchAliases('Coffee')).single.product.id,
        'coffee-33',
      );
      expect((await adapter.getProductComparison('coffee')).history.length, 1);
    },
  );

  test(
    'profile, photos, aliases, receipts and zero override survive closing and reopening',
    () async {
      final photo = File(p.join(root.path, 'product-photo.jpg'));
      final logo = File(p.join(root.path, 'store-logo.png'));
      await photo.writeAsString('original product photo bytes');
      await logo.writeAsString('original store logo bytes');
      await adapter.saveProduct(
        Product(
          id: 'coffee',
          name: coffee.name,
          brand: coffee.brand,
          variant: coffee.variant,
          size: coffee.size,
          photoPath: photo.path,
          markupPercent: 0,
          sellingPriceCents: 1000,
        ),
      );
      await adapter.updateStoreProfile(
        StoreProfile(
          name: 'Tindahan ni Ana',
          ownerName: 'Ana',
          photoPath: logo.path,
          defaultMarkupPercent: 20,
        ),
      );
      final input = await draft();
      final saved = await adapter.saveConfirmedReceipt(input);
      await adapter.close();
      await photo.delete();
      await logo.delete();
      await File(input.imagePath).delete();
      adapter = await openAdapter();
      db = await databaseFactoryFfi.openDatabase(databasePath);
      final profile = await adapter.getStoreProfile();
      final product = (await adapter.getProductById('coffee'))!;
      expect(profile.name, 'Tindahan ni Ana');
      expect(profile.defaultMarkupPercent, 20);
      expect(
        await File(profile.photoPath!).readAsString(),
        'original store logo bytes',
      );
      expect(
        await File(product.photoPath!).readAsString(),
        'original product photo bytes',
      );
      expect(
        (await adapter.getAliases('coffee')).single.description,
        'COF ORIG 26G',
      );
      final comparison = await adapter.getProductComparison('coffee');
      expect(comparison.effectiveMarkupPercent, 0);
      expect(comparison.latestPrices.single.purchase.netAmountCents, 16800);
      expect(
        await File(
          (await adapter.getReceipt(saved.receiptId)).receipt.imagePath,
        ).exists(),
        isTrue,
      );
      await adapter.updateStoreProfile(
        StoreProfile(
          name: profile.name,
          photoPath: profile.photoPath,
          defaultMarkupPercent: 40,
        ),
      );
      await adapter.saveProduct(
        Product(
          id: product.id,
          name: product.name,
          brand: product.brand,
          variant: product.variant,
          size: product.size,
          photoPath: product.photoPath,
          markupPercent: 35,
          sellingPriceCents: 1200,
        ),
      );
      expect(
        (await adapter.getProductComparison(
          'coffee',
        )).latestPrices.single.purchase.netAmountCents,
        16800,
      );
      expect(
        (await adapter.getReceipt(saved.receiptId)).lines.single.quantity,
        2,
      );
    },
  );

  test(
    'failed photo copy and database update preserve existing references and files',
    () async {
      final photo = File(p.join(root.path, 'photo.jpg'));
      await photo.writeAsString('old photo');
      await adapter.saveProduct(
        Product(
          id: coffee.id,
          name: coffee.name,
          brand: coffee.brand,
          variant: coffee.variant,
          size: coffee.size,
          photoPath: photo.path,
        ),
      );
      final old = (await adapter.getProductById(coffee.id))!;
      await expectLater(
        adapter.saveProduct(
          Product(
            id: coffee.id,
            name: coffee.name,
            brand: coffee.brand,
            variant: coffee.variant,
            size: coffee.size,
            photoPath: p.join(root.path, 'missing.jpg'),
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(
        (await adapter.getProductById(coffee.id))!.photoPath,
        old.photoPath,
      );
      final replacement = File(p.join(root.path, 'replacement.jpg'));
      await replacement.writeAsString('new photo');
      await db.execute(
        "CREATE TRIGGER reject_product_update BEFORE UPDATE ON products BEGIN SELECT RAISE(ABORT, 'injected photo failure'); END",
      );
      await expectLater(
        adapter.saveProduct(
          Product(
            id: coffee.id,
            name: coffee.name,
            brand: coffee.brand,
            variant: coffee.variant,
            size: coffee.size,
            photoPath: replacement.path,
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        (await adapter.getProductById(coffee.id))!.photoPath,
        old.photoPath,
      );
      expect(await File(old.photoPath!).readAsString(), 'old photo');
      expect((await persistentFiles()).length, 1);
      await db.execute('DROP TRIGGER reject_product_update');
      await adapter.saveProduct(
        Product(
          id: coffee.id,
          name: coffee.name,
          brand: coffee.brand,
          variant: coffee.variant,
          size: coffee.size,
          photoPath: replacement.path,
        ),
      );
      expect(await File(old.photoPath!).exists(), isFalse);
      expect(
        await File(
          (await adapter.getProductById(coffee.id))!.photoPath!,
        ).readAsString(),
        'new photo',
      );
    },
  );

  test(
    'history identity cannot change into a different size while pricing edits remain allowed',
    () async {
      await adapter.saveConfirmedReceipt(await draft());
      await expectLater(
        adapter.saveProduct(
          Product(
            id: coffee.id,
            name: coffee.name,
            brand: coffee.brand,
            variant: coffee.variant,
            size: '33g',
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
      expect((await adapter.getProductById(coffee.id))!.size, '26g');
      await adapter.saveProduct(
        Product(
          id: coffee.id,
          name: 'Updated display name',
          brand: 'brand x',
          variant: ' original ',
          size: '26g',
          markupPercent: 0,
        ),
      );
      final comparison = await adapter.getProductComparison('coffee');
      expect(comparison.effectiveMarkupPercent, 0);
      expect(comparison.history.single.purchase.costPerPieceCents, 840);
    },
  );

  test(
    'comparisons retain every same-day purchase and select latest by explicit policy',
    () async {
      await adapter.saveConfirmedReceipt(
        await draft(
          operation: 'old',
          gross: 16000,
          discount: 0,
          date: DateTime(2026, 10, 1),
        ),
      );
      await adapter.saveConfirmedReceipt(
        await draft(
          operation: 'known',
          gross: 17000,
          discount: 0,
          date: DateTime(2026, 10, 8, 17),
          hasTime: true,
        ),
      );
      await adapter.saveConfirmedReceipt(
        await draft(
          operation: 'unknown',
          gross: 18000,
          discount: 0,
          date: DateTime(2026, 10, 8),
        ),
      );
      await adapter.saveConfirmedReceipt(
        await draft(
          operation: 'other',
          supplier: 'Supplier B',
          gross: 15600,
          discount: 0,
          date: DateTime(2026, 10, 5),
        ),
      );
      final comparison = await adapter.getProductComparison('coffee');
      expect(comparison.history.length, 4);
      expect(
        comparison.latestPrices.first.purchase.supplier.name,
        'Supplier B',
      );
      final latestA = comparison.latestPrices.firstWhere(
        (row) => row.purchase.supplier.name == 'Supplier A',
      );
      expect(latestA.purchase.costPerPieceCents, 900);
      expect(comparison.lowestHistorical!.costPerPieceCents, 780);
      final sameDay = comparison.history
          .where(
            (entry) =>
                entry.purchase.supplier.name == 'Supplier A' &&
                entry.purchase.purchasedAt.day == 8,
          )
          .toList();
      expect(sameDay.map((entry) => entry.purchase.costPerPieceCents), [
        850,
        900,
      ]);
      expect(sameDay.every((entry) => entry.orderingNote != null), isTrue);
      final restock = await adapter.calculateRestock(
        productId: 'coffee',
        targetPieces: 21,
        additionalCost: 0,
        additionalCostsCents: {latestA.purchase.supplier.id: 3000},
      );
      expect(
        restock.suppliers
            .firstWhere(
              (estimate) => estimate.purchase.supplier.name == 'Supplier A',
            )
            .totalCents,
        30000,
      );
    },
  );

  test(
    'search filters real products and receipt sources and escapes wildcard input',
    () async {
      await adapter.saveConfirmedReceipt(await draft(number: 'OR-123'));
      expect((await adapter.getProducts(query: '26g')).single.id, 'coffee');
      expect((await adapter.getProducts(query: '%')), isEmpty);
      expect((await adapter.getRecentReceipts(query: 'OR-123')).length, 1);
      expect((await adapter.getRecentReceipts(query: 'COF ORIG')).length, 1);
      expect(await adapter.getRecentReceipts(query: '%'), isEmpty);
    },
  );

  test(
    'basket alternatives include saved suppliers without any selected-product price',
    () async {
      await adapter.saveSupplier(
        const Supplier(
          id: 'unknown-supplier',
          name: 'Unpriced supplier',
          branch: 'North',
        ),
      );
      await adapter.saveConfirmedReceipt(await draft());
      final basket = await adapter.calculateBasket(
        {'coffee': 21},
        additionalCostsCents: {'unknown-supplier': 3000},
      );
      expect(basket.groups.length, 1);
      final unknown = basket.alternatives.firstWhere(
        (alternative) => alternative.supplier.id == 'unknown-supplier',
      );
      expect(unknown.items, isEmpty);
      expect(unknown.missingProducts.single.id, 'coffee');
      expect(unknown.additionalCostCents, 3000);
      expect(basket.alternatives.length, 2);
    },
  );

  test(
    'OCR may use a transformed image while preserving the source for receipt evidence',
    () async {
      final input = await draft();
      final transformed = File(p.join(root.path, 'rotated.jpg'));
      await transformed.writeAsString('transformed image');
      final parsed = await adapter.processReceiptImage(
        input.imagePath,
        recognitionImagePath: transformed.path,
      );
      expect(ocr.lastImagePath, transformed.path);
      expect(parsed.imagePath, input.imagePath);
      expect(parsed.recognitionImagePath, transformed.path);
      expect(parsed.dateConfirmed, isFalse);
      expect(await count('receipts'), 0);
    },
  );
}
