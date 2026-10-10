import 'dart:convert';
import 'package:printing/printing.dart';
import 'package:reseebo_app/features/insights/services/suggested_suppliers.dart';
import 'package:reseebo_app/features/insights/services/store_insights_pdf.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/features/insights/models/store_insights.dart';
import 'package:reseebo_app/features/insights/services/store_insights_service.dart';
import 'package:reseebo_app/features/insights/screens/insights_screen.dart';
import 'package:reseebo_app/features/dashboard/screens/dashboard_screen.dart';

const product = Product(
  id: 'p',
  name: 'Coffee',
  brand: 'Brand',
  variant: 'Original',
  size: '26g',
);
const supplier = Supplier(id: 's', name: 'Shop');
PurchaseRecord purchase(
  String id,
  DateTime date, {
  String receipt = 'r',
  int amount = 1000,
}) => PurchaseRecord(
  id: id,
  receiptId: receipt,
  productId: 'p',
  supplier: supplier,
  purchasedAt: date,
  hasPurchaseTime: false,
  recordedAt: date,
  originalDescription: 'Coffee',
  quantity: 2,
  unit: PurchaseUnit.piece,
  piecesPerPack: 1,
  netAmountCents: amount,
  imagePath: 'receipt.jpg',
);
ProductComparisonData comparison(
  List<PriceHistoryRecord> history, {
  List<SupplierPriceRow> prices = const [],
}) => ProductComparisonData(
  product: product,
  profile: const StoreProfile(),
  latestPrices: prices,
  history: history,
);

class EmptyAdapter extends MockReseeboDataAdapter {
  bool fail = false;
  @override
  Future<List<Product>> getProducts({String? query}) async {
    if (fail) throw Exception('storage unavailable');
    return [];
  }
}

void main() {
  test(
    'supplier suggestions group latest winners, include ties, exclude sole suppliers',
    () {
      final first = purchase('a', DateTime(2026, 10, 8));
      final other = PurchaseRecord(
        id: 'b',
        receiptId: 'b',
        productId: 'p',
        supplier: const Supplier(id: 'b', name: 'Supplier B'),
        purchasedAt: DateTime(2026, 10, 9),
        hasPurchaseTime: false,
        recordedAt: DateTime(2026, 10, 9),
        originalDescription: 'Coffee',
        quantity: 2,
        unit: PurchaseUnit.piece,
        piecesPerPack: 1,
        netAmountCents: 1000,
        imagePath: 'b.jpg',
      );
      final sole = comparison(
        [],
        prices: [SupplierPriceRow(purchase: first, bestCostPerPieceCents: 500)],
      );
      expect(suggestedSuppliers([sole]), isEmpty);
      final tied = comparison(
        [],
        prices: [
          SupplierPriceRow(purchase: first, bestCostPerPieceCents: 500),
          SupplierPriceRow(purchase: other, bestCostPerPieceCents: 500),
        ],
      );
      final groups = suggestedSuppliers([tied]);
      expect(groups.length, 2);
      expect(groups.every((group) => group.products.single.tied), isTrue);
      expect(
        groups.last.products.single.price.latestPurchaseDate,
        DateTime(2026, 10, 9),
      );
      final higher = purchase('higher', DateTime(2026, 10, 10), amount: 1200);
      final winner = comparison(
        [],
        prices: [
          SupplierPriceRow(purchase: higher, bestCostPerPieceCents: 500),
          SupplierPriceRow(purchase: other, bestCostPerPieceCents: 500),
        ],
      );
      expect(suggestedSuppliers([winner]).single.supplier.id, 'b');
      expect(suggestedSuppliers([winner]).single.products.single.tied, isFalse);
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('net.nfet.printing'),
          (call) async =>
              call.method == 'printingInfo' ? <String, dynamic>{} : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('net.nfet.printing'),
          null,
        );
  });
  test('first purchase remains visible in supplier tables', () {
    final row = purchase('first', DateTime(2026, 10, 10));
    final result = StoreInsightsService.summarize(
      [
        comparison(
          [PriceHistoryRecord(purchase: row)],
          prices: [SupplierPriceRow(purchase: row, bestCostPerPieceCents: 500)],
        ),
      ],
      InsightPeriod.last30Days,
      DateTime(2026, 10, 10),
    );
    expect(result.changes, isEmpty);
    expect(result.comparisons.single.latestPrices.single.purchase.id, 'first');
  });

  testWidgets('store button opens locally generated PDF', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DashboardScreen(dataAdapter: MockReseeboDataAdapter())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('View insights'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(find.byType(InsightsScreen), findsOneWidget);
    expect(find.byType(PdfPreview), findsOneWidget);
    expect(find.text('Store insights PDF'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PDF builds empty and multiple-page tables with bundled font', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final adapter = MockReseeboDataAdapter();
      final data = await StoreInsightsService(adapter).load();
      final summary = StoreInsightsService.summarize(
        data,
        InsightPeriod.allHistory,
        DateTime(2026, 10, 10),
      );
      final sample = await StoreInsightsPdf.build(
        insights: summary,
        storeName: 'Sari-sari Store',
        period: InsightPeriod.allHistory,
        generatedAt: DateTime(2026, 10, 10, 10),
      );
      expect(ascii.decode(sample.take(5).toList()), '%PDF-');
      final long = await StoreInsightsPdf.build(
        insights: StoreInsights(
          spentCents: 0,
          receiptCount: 0,
          supplierCount: 0,
          changes: [for (var i = 0; i < 100; i++) ...summary.changes],
          comparisons: [for (var i = 0; i < 30; i++) ...summary.comparisons],
        ),
        storeName: 'A long store name for local supplier comparison',
        period: InsightPeriod.allHistory,
        generatedAt: DateTime(2026, 10, 10),
      );
      expect(ascii.decode(long.take(5).toList()), '%PDF-');
      final empty = await StoreInsightsPdf.build(
        insights: const StoreInsights(
          spentCents: 0,
          receiptCount: 0,
          supplierCount: 0,
          changes: [],
          comparisons: [],
        ),
        storeName: 'Empty Store',
        period: InsightPeriod.last30Days,
        generatedAt: DateTime(2026, 10, 10),
      );
      expect(ascii.decode(empty.take(5).toList()), '%PDF-');
    });
  });

  test(
    'calendar periods include boundary and deduplicate receipts and lines',
    () {
      final data = [
        comparison([
          PriceHistoryRecord(
            purchase: purchase('old', DateTime(2026, 9, 10), receipt: 'old'),
          ),
          PriceHistoryRecord(purchase: purchase('a', DateTime(2026, 9, 11))),
          PriceHistoryRecord(
            purchase: purchase('b', DateTime(2026, 10, 10, 23)),
            previousCostPerPieceCents: 400,
          ),
          PriceHistoryRecord(
            purchase: purchase('future', DateTime(2026, 10, 11)),
          ),
        ]),
      ];
      final summary = StoreInsightsService.summarize(
        [...data, ...data],
        InsightPeriod.last30Days,
        DateTime(2026, 10, 10),
      );
      expect(summary.spentCents, 2000);
      expect(summary.receiptCount, 1);
      expect(summary.supplierCount, 1);
      expect(summary.changes.single.history.changeCents, 100);
      expect(
        StoreInsightsService.summarize(
          data,
          InsightPeriod.thisMonth,
          DateTime(2026, 10, 10),
        ).spentCents,
        1000,
      );
      expect(
        StoreInsightsService.summarize(
          data,
          InsightPeriod.allHistory,
          DateTime(2026, 10, 10),
        ).spentCents,
        3000,
      );
    },
  );

  test(
    'supplier comparisons remain independent of period and retain tied rows',
    () {
      final first = purchase('a', DateTime(2020));
      final second = PurchaseRecord(
        id: 'b',
        receiptId: 'other',
        productId: 'p',
        supplier: const Supplier(id: 'other', name: 'Other shop'),
        purchasedAt: DateTime(2021),
        hasPurchaseTime: false,
        recordedAt: DateTime(2021),
        originalDescription: 'Coffee',
        quantity: 2,
        unit: PurchaseUnit.piece,
        piecesPerPack: 1,
        netAmountCents: 1000,
        imagePath: 'photo.jpg',
      );
      final summary = StoreInsightsService.summarize(
        [
          comparison(
            [],
            prices: [
              SupplierPriceRow(purchase: first, bestCostPerPieceCents: 500),
              SupplierPriceRow(purchase: second, bestCostPerPieceCents: 500),
            ],
          ),
        ],
        InsightPeriod.thisMonth,
        DateTime(2026, 10, 10),
      );
      expect(summary.receiptCount, 0);
      expect(
        summary.comparisons.single.latestPrices.where((r) => r.isLowest).length,
        2,
      );
    },
  );

  testWidgets('empty insights fit narrow screen and failed loads can retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final adapter = EmptyAdapter()..fail = true;
    await tester.pumpWidget(
      MaterialApp(home: InsightsScreen(adapter: adapter)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    adapter.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(find.text('Purchase summary'), findsNothing);
    expect(find.byType(PdfPreview), findsOneWidget);
    expect(find.text('Store insights PDF'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
