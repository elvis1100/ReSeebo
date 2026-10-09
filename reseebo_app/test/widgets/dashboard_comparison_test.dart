import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reseebo_app/core/adapters/i_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/services/pricing_service.dart';
import 'package:reseebo_app/core/theme/app_theme.dart';
import 'package:reseebo_app/features/comparison/screens/product_comparison_screen.dart';
import 'package:reseebo_app/features/comparison/state/comparison_controller.dart';
import 'package:reseebo_app/features/dashboard/screens/dashboard_screen.dart';
import 'package:reseebo_app/features/dashboard/state/dashboard_controller.dart';
import 'package:reseebo_app/features/planner/state/basket_controller.dart';
import 'package:reseebo_app/features/planner/widgets/basket_results.dart';
import 'package:reseebo_app/features/planner/widgets/profit_calculator_card.dart';

const product = Product(
  id: 'coffee',
  name: 'Coffee original',
  brand: 'Brand X',
  variant: 'Original',
  size: '26 g',
  markupPercent: 0,
);
const supplierA = Supplier(id: 'a', name: 'Grocery A', branch: 'Main');
const supplierB = Supplier(id: 'b', name: 'Grocery B');
const missingProduct = Product(
  id: 'milk',
  name: 'Milk',
  brand: 'Brand Y',
  variant: 'Full cream',
  size: '100 g',
);

PurchaseRecord purchase(
  String id,
  Supplier supplier,
  int cents,
  int day, {
  int sequence = 1,
}) => PurchaseRecord(
  id: id,
  receiptId: 'receipt-$id',
  productId: product.id,
  supplier: supplier,
  purchasedAt: DateTime(2026, 10, day),
  hasPurchaseTime: false,
  recordedAt: DateTime(2026, 10, day, 18),
  originalDescription: 'COFFEE ORIG 26G',
  quantity: 1,
  unit: PurchaseUnit.pack,
  piecesPerPack: 10,
  netAmountCents: cents,
  imagePath: '/missing.jpg',
  sequence: sequence,
);

class FixtureAdapter extends IReseeboDataAdapter {
  FixtureAdapter({this.savedProduct = product, this.defaultMarkup = 20});
  Product savedProduct;
  double? defaultMarkup;
  bool failReads = false;
  Completer<List<Receipt>>? delayedReceipts;
  Completer<RestockEstimate>? delayedRestock;
  final records = [
    purchase('old-a', supplierA, 7000, 5),
    purchase('new-a', supplierA, 8400, 9),
    purchase('new-b', supplierB, 7800, 8),
  ];
  @override
  Future<StoreProfile> getStoreProfile() async => StoreProfile(
    name: 'Aling Lina Store',
    defaultMarkupPercent: defaultMarkup,
  );
  @override
  Future<List<Receipt>> getRecentReceipts({
    int limit = 200,
    String? query,
  }) async {
    if (failReads) throw const AppException('Local read failed');
    if (delayedReceipts != null) return delayedReceipts!.future;
    return [];
  }

  @override
  Future<List<Product>> getProducts({String? query}) async => [savedProduct];
  @override
  Future<List<Supplier>> getSuppliers() async => [supplierA, supplierB];
  @override
  Future<ProductComparisonData> getProductComparison(String productId) async =>
      PricingService.comparison(savedProduct, await getStoreProfile(), records);
  @override
  Future<RestockEstimate> calculateRestock({
    required String productId,
    required int targetPieces,
    required double additionalCost,
    Map<String, int> additionalCostsCents = const {},
  }) async {
    if (delayedRestock != null) return delayedRestock!.future;
    final comparison = await getProductComparison(productId);
    return RestockEstimate(
      product: savedProduct,
      targetPieces: targetPieces,
      suppliers: comparison.latestPrices
          .map(
            (row) => PricingService.estimatePurchase(
              row.purchase,
              targetPieces,
              additionalCostCents:
                  additionalCostsCents[row.purchase.supplier.id] ?? 0,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<BasketEstimate> calculateBasket(
    Map<String, int> targetPieces, {
    Map<String, int> additionalCostsCents = const {},
  }) async {
    return PricingService.basket({
      savedProduct: await calculateRestock(
        productId: product.id,
        targetPieces: targetPieces[product.id]!,
        additionalCost: 0,
      ),
      if (targetPieces.containsKey(missingProduct.id))
        missingProduct: RestockEstimate(
          product: missingProduct,
          targetPieces: targetPieces[missingProduct.id]!,
          suppliers: [],
        ),
    }, additionalCostsCents: additionalCostsCents);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget app(Widget screen, {double scale = 1}) => MaterialApp(
  theme: AppTheme.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: screen,
);

void main() {
  setUpAll(() => initializeDateFormatting('en_PH'));
  testWidgets('dashboard first launch shows honest empty ledger at 360dp', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(DashboardScreen(adapter: FixtureAdapter()), scale: 1.3),
    );
    await tester.pumpAndSettle();
    expect(find.text('Aling Lina Store'), findsOneWidget);
    expect(find.text('Your receipt ledger starts here'), findsOneWidget);
    expect(find.text('Scan receipt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local read failure shows retry and recovers', (tester) async {
    final adapter = FixtureAdapter()..failReads = true;
    await tester.pumpWidget(app(DashboardScreen(adapter: adapter)));
    await tester.pumpAndSettle();
    expect(find.text('Local read failed'), findsOneWidget);
    adapter.failReads = false;
    await tester.ensureVisible(find.text('Try again'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Your receipt ledger starts here'), findsOneWidget);
  });

  test(
    'dashboard selects newest dated cost rather than grouped first history',
    () async {
      final controller = DashboardController(FixtureAdapter());
      controller.tab = DashboardTab.products;
      await controller.load();
      expect(controller.latestCosts[product.id], 840);
      expect(controller.latestCostDates[product.id], DateTime(2026, 10, 9));
      controller.dispose();
    },
  );

  test(
    'older dashboard load cannot overwrite newly selected product tab',
    () async {
      final adapter = FixtureAdapter()
        ..delayedReceipts = Completer<List<Receipt>>();
      final controller = DashboardController(adapter);
      final earlier = controller.load();
      await Future<void>.delayed(Duration.zero);
      controller.selectTab(DashboardTab.products);
      await Future<void>.delayed(Duration.zero);
      adapter.delayedReceipts!.complete([]);
      await earlier;
      expect(controller.tab, DashboardTab.products);
      expect(controller.products, hasLength(1));
      expect(controller.latestCosts[product.id], 840);
      controller.dispose();
    },
  );

  testWidgets('comparison supplier cards fit narrow enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        ProductComparisonScreen(
          adapter: FixtureAdapter(),
          productId: product.id,
        ),
        scale: 1.3,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Latest recorded supplier prices'), findsOneWidget);
    expect(find.text('Grocery B'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView).first, const Offset(0, -750));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test(
    '0% product override wins; selling at zero has undefined margin',
    () async {
      final controller = ComparisonController(FixtureAdapter(), product.id);
      await controller.load();
      expect(controller.markupInput, '0.0');
      expect(controller.suggestedPriceCents, 780);
      controller.changePricing(selling: '0.00');
      expect(controller.profit!.grossProfitCents, -780);
      expect(controller.profit!.marginPercent, isNull);
      controller.dispose();
    },
  );

  test('comparison reload cancels an in-flight restock estimate', () async {
    final adapter = FixtureAdapter()
      ..delayedRestock = Completer<RestockEstimate>();
    final controller = ComparisonController(adapter, product.id);
    await controller.load();
    controller.changeRestock(quantity: '11');
    final pending = controller.calculateRestock();
    expect(controller.calculating, isTrue);
    await controller.load();
    adapter.delayedRestock!.complete(
      const RestockEstimate(product: product, targetPieces: 11, suppliers: []),
    );
    await pending;
    expect(controller.restock, isNull);
    expect(controller.calculating, isFalse);
    controller.dispose();
  });

  testWidgets(
    'unset markup requests input while saved owner price estimates profit',
    (tester) async {
      final ownerProduct = Product(
        id: product.id,
        name: product.name,
        brand: product.brand,
        variant: product.variant,
        size: product.size,
        sellingPriceCents: 1000,
      );
      final controller = ComparisonController(
        FixtureAdapter(savedProduct: ownerProduct, defaultMarkup: null),
        product.id,
      );
      await controller.load();
      expect(controller.suggestedPriceCents, isNull);
      expect(controller.profit!.grossProfitCents, 220);
      await tester.pumpWidget(
        app(
          Scaffold(
            body: SingleChildScrollView(
              child: ProfitCalculatorCard(controller: controller),
            ),
          ),
        ),
      );
      expect(find.textContaining('Choose a markup percentage'), findsOneWidget);
      expect(find.text('Estimated gross profit ₱2.20 / pc'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  test(
    'restock rounds whole packs and includes both baseline extras',
    () async {
      final controller = ComparisonController(FixtureAdapter(), product.id);
      await controller.load();
      controller.changeRestock(
        quantity: '11',
        supplierId: supplierA.id,
        extra: '10.00',
      );
      controller.changeRestock(supplierId: supplierB.id, extra: '30.00');
      await controller.calculateRestock();
      final best = controller.restock!.suppliers.first;
      expect(best.purchase.supplier.id, supplierB.id);
      expect(best.purchasedPieces, 20);
      expect(best.subtotalCents, 15600);
      expect(controller.baselineSupplierId, supplierA.id);
      expect(controller.productSavings(best), 1200);
      expect(controller.netSavings(best), -800);
      controller.changePricing(includeExtra: true);
      expect(controller.costUsedCents, 930);
      controller.changeRestock(quantity: '12');
      expect(controller.restock, isNull);
      controller.dispose();
    },
  );

  testWidgets('missing basket prices stay unknown with partial totals', (
    tester,
  ) async {
    final controller = BasketController(FixtureAdapter());
    await controller.load();
    controller.changeQuantity(product.id, '11');
    controller.changeQuantity(missingProduct.id, '10');
    controller.changeExtra(supplierB.id, '30.00');
    await controller.calculate();
    expect(controller.estimate!.missingProducts, [missingProduct]);
    expect(controller.bestCompleteAlternative, isNull);
    expect(controller.estimate!.totalCents, 18600);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: SingleChildScrollView(
            child: BasketResults(controller: controller, onReceipt: (_) {}),
          ),
        ),
      ),
    );
    expect(find.text('Known estimated total · partial:'), findsWidgets);
    expect(find.textContaining('Price unknown'), findsWidgets);
    expect(
      find.textContaining('Lowest complete single-supplier'),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  test('basket complete alternative comparison respects extra costs', () async {
    final controller = BasketController(FixtureAdapter());
    await controller.load();
    controller.changeQuantity(product.id, '11');
    controller.changeExtra(supplierB.id, '30.00');
    await controller.calculate();
    expect(controller.estimate!.groups.first.supplier.id, supplierB.id);
    expect(controller.bestCompleteAlternative!.supplier.id, supplierA.id);
    expect(controller.bestCompleteAlternative!.knownTotalCents, 16800);
    expect(controller.completeAlternativeSavings, 1800);
    controller.dispose();
  });
}
