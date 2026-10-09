import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reseebo/core/adapters/i_reseebo_data_adapter.dart';
import 'package:reseebo/core/adapters/sqlite_reseebo_data_adapter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sqlite_adapter_test.dart' as fixtures;

class ComparisonFallback extends IReseeboDataAdapter {
  ComparisonFallback(this.storage);
  final SqliteReseeboDataAdapter storage;

  @override
  Future<ProductComparisonData> getProductComparison(String id) =>
      storage.getProductComparison(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root;
  late SqliteReseeboDataAdapter adapter;
  var recordedMillis = 1000;

  const secondProduct = Product(
    id: 'second',
    name: 'Second product',
    brand: 'Brand Y',
    variant: 'Original',
    size: '100g',
  );
  const noHistory = Product(
    id: 'unbought',
    name: 'Unbought product',
    brand: 'Brand Z',
    variant: 'Original',
    size: '200g',
  );

  Future<void> save({
    required String operation,
    String productId = 'coffee',
    String supplier = 'Supplier A',
    required DateTime date,
    bool hasTime = false,
    required int gross,
    int? recorded,
  }) async {
    if (recorded != null) recordedMillis = recorded;
    final image = File(p.join(root.path, '$operation.jpg'));
    await image.writeAsString('distinct original $operation');
    await adapter.saveConfirmedReceipt(
      ReceiptDraft(
        operationId: operation,
        imagePath: image.path,
        supplierName: supplier,
        purchasedAt: date,
        hasPurchaseTime: hasTime,
        dateConfirmed: true,
        lines: [
          ParsedLineItem(
            description: 'Exact receipt product',
            productId: productId,
            quantity: 2,
            unit: PurchaseUnit.pack,
            piecesPerPack: 10,
            grossAmountCents: gross,
            confirmed: true,
          ),
        ],
      ),
    );
  }

  Future<void> expectFallbackAgreement(List<String> ids) async {
    final actual = await adapter.getLatestProductCosts(ids);
    final fallback = await ComparisonFallback(
      adapter,
    ).getLatestProductCosts(ids);
    expect(actual.keys.toSet(), fallback.keys.toSet());
    for (final id in actual.keys) {
      expect(actual[id]!.costPerPieceCents, fallback[id]!.costPerPieceCents);
      expect(actual[id]!.purchasedAt, fallback[id]!.purchasedAt);
    }
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('reseebo-cost-summary-');
    recordedMillis = 1000;
    adapter = await SqliteReseeboDataAdapter.open(
      databaseFactory: databaseFactoryFfi,
      databasePath: p.join(root.path, 'records.sqlite'),
      mediaDirectory: Directory(p.join(root.path, 'media')),
      ocrService: fixtures.FakeOcr(),
      clock: () =>
          DateTime.fromMillisecondsSinceEpoch(recordedMillis, isUtc: true),
    );
    for (final product in [fixtures.coffee, secondProduct, noHistory]) {
      await adapter.saveProduct(product);
    }
  });

  tearDown(() async {
    await adapter.close();
    await root.delete(recursive: true);
  });

  test(
    'cost summaries limit IDs, omit unbought products and retain fractions',
    () async {
      await save(
        operation: 'coffee',
        date: DateTime(2026, 10, 8),
        gross: 16901,
      );
      await save(
        operation: 'other',
        productId: 'second',
        date: DateTime(2026, 10, 9),
        gross: 20000,
      );
      expect(await adapter.getLatestProductCosts([]), isEmpty);
      final costs = await adapter.getLatestProductCosts([
        'coffee',
        'coffee',
        'unbought',
        'absent',
      ]);
      expect(costs.keys, ['coffee']);
      expect(costs['coffee']!.costPerPieceCents, 16901 / 20);
      expect(costs['coffee']!.purchasedAt, DateTime(2026, 10, 8));
      await expectFallbackAgreement(['coffee', 'second', 'unbought']);
    },
  );

  test(
    'requested IDs spanning legacy SQLite bind limits are batched',
    () async {
      await save(
        operation: 'batched',
        date: DateTime(2026, 10, 8),
        gross: 16901,
      );
      final ids = List.generate(1100, (index) => 'absent-$index');
      ids[1000] = 'coffee';
      final costs = await adapter.getLatestProductCosts(ids);
      expect(costs.keys, ['coffee']);
      expect(costs['coffee']!.costPerPieceCents, 16901 / 20);
    },
  );

  test(
    'unknown times preserve supplier saved order and global recorded ties',
    () async {
      await save(
        operation: 'a-known',
        date: DateTime(2026, 10, 8, 21),
        hasTime: true,
        gross: 16000,
        recorded: 5000,
      );
      await save(
        operation: 'a-unknown',
        date: DateTime(2026, 10, 8),
        gross: 18000,
        recorded: 3000,
      );
      await save(
        operation: 'b-known',
        supplier: 'Supplier B',
        date: DateTime(2026, 10, 8, 22),
        hasTime: true,
        gross: 20000,
        recorded: 2000,
      );
      final first = await adapter.getLatestProductCosts(['coffee']);
      // Supplier A's later sequence wins even after its clock moved backwards;
      // globally the missing time makes recorded-at beat Supplier B's 22:00.
      expect(first['coffee']!.costPerPieceCents, 900);
      await expectFallbackAgreement(['coffee']);
      await save(
        operation: 'c-tied',
        supplier: 'Supplier C',
        date: DateTime(2026, 10, 8),
        gross: 22000,
        recorded: 3000,
      );
      expect(
        (await adapter.getLatestProductCosts([
          'coffee',
        ]))['coffee']!.costPerPieceCents,
        1100,
      );
      await expectFallbackAgreement(['coffee']);
      await save(
        operation: 'older-imported-later',
        supplier: 'Supplier D',
        date: DateTime(2026, 10, 7, 23),
        hasTime: true,
        gross: 24000,
        recorded: 9000,
      );
      expect(
        (await adapter.getLatestProductCosts([
          'coffee',
        ]))['coffee']!.costPerPieceCents,
        1100,
      );
      await expectFallbackAgreement(['coffee']);
    },
  );

  test(
    'known candidate times outrank saved time after supplier selection',
    () async {
      await save(
        operation: 'a-old-unknown',
        date: DateTime(2026, 10, 8),
        gross: 16000,
      );
      await save(
        operation: 'a-latest-known',
        date: DateTime(2026, 10, 8, 9),
        hasTime: true,
        gross: 18000,
        recorded: 6000,
      );
      await save(
        operation: 'b-latest-known',
        supplier: 'Supplier B',
        date: DateTime(2026, 10, 8, 12),
        hasTime: true,
        gross: 20000,
        recorded: 2000,
      );
      // Only each supplier's latest candidate controls the dashboard's time rule.
      expect(
        (await adapter.getLatestProductCosts([
          'coffee',
        ]))['coffee']!.costPerPieceCents,
        1000,
      );
      await expectFallbackAgreement(['coffee']);
      await save(
        operation: 'b-earlier-time-saved-later',
        supplier: 'Supplier B',
        date: DateTime(2026, 10, 8, 10),
        hasTime: true,
        gross: 22000,
        recorded: 8000,
      );
      expect(
        (await adapter.getLatestProductCosts([
          'coffee',
        ]))['coffee']!.costPerPieceCents,
        1000,
      );
      await expectFallbackAgreement(['coffee']);
      await save(
        operation: 'b-same-time-saved-later',
        supplier: 'Supplier B',
        date: DateTime(2026, 10, 8, 12),
        hasTime: true,
        gross: 24000,
        recorded: 1000,
      );
      expect(
        (await adapter.getLatestProductCosts([
          'coffee',
        ]))['coffee']!.costPerPieceCents,
        1200,
      );
      await expectFallbackAgreement(['coffee']);
    },
  );
}
