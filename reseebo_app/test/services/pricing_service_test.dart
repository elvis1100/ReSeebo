import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo/core/errors/app_exception.dart';
import 'package:reseebo/core/models/models.dart';
import 'package:reseebo/core/services/pricing_service.dart';

const product = Product(
  id: 'coffee',
  name: 'Coffee',
  brand: 'Brand X',
  variant: 'Original',
  size: '26g',
);
const supplierA = Supplier(id: 'a', name: 'Supplier A');
const supplierB = Supplier(id: 'b', name: 'Supplier B');

PurchaseRecord purchase({
  String id = 'line',
  Supplier supplier = supplierA,
  int amount = 16800,
  int quantity = 2,
  int pieces = 10,
  PurchaseUnit unit = PurchaseUnit.pack,
  DateTime? date,
  bool hasTime = false,
  int sequence = 1,
}) => PurchaseRecord(
  id: id,
  receiptId: 'receipt-$id',
  productId: product.id,
  supplier: supplier,
  purchasedAt: date ?? DateTime(2026, 10, 8),
  hasPurchaseTime: hasTime,
  recordedAt: DateTime.utc(2026, 10, 9),
  originalDescription: 'BRAND X ORIG 26G',
  quantity: quantity,
  unit: unit,
  piecesPerPack: pieces,
  netAmountCents: amount,
  imagePath: '/receipt.jpg',
  sequence: sequence,
);

void main() {
  test(
    'restock pays for whole packs and preserves the recorded net pack price',
    () {
      final result = PricingService.estimatePurchase(
        purchase(),
        21,
        additionalCostCents: 3000,
      );
      expect(result.packsToBuy, 3);
      expect(result.purchasedPieces, 30);
      expect(result.subtotalCents, 25200);
      expect(result.totalCents, 28200);
    },
  );

  test('fractional centavo costs round only once at final payment', () {
    final result = PricingService.estimatePurchase(
      purchase(amount: 100, quantity: 3, pieces: 1, unit: PurchaseUnit.piece),
      6,
    );
    expect(result.subtotalCents, 200);
    final packResult = PricingService.estimatePurchase(
      purchase(amount: 100, quantity: 3, pieces: 10),
      40,
    );
    expect(packResult.subtotalCents, 133);
  });

  test('suggested prices and profit separate markup from gross margin', () {
    expect(PricingService.suggestedSellingPriceCents(800, 20), 960);
    expect(PricingService.suggestedSellingPriceCents(800, 0), 800);
    final result = PricingService.profit(800, 1000);
    expect(result.grossProfitCents, 200);
    expect(result.markupPercent, 25);
    expect(result.marginPercent, 20);
    expect(PricingService.profit(800, 0).marginPercent, isNull);
    expect(
      () => PricingService.suggestedSellingPriceCents(800, double.nan),
      throwsA(isA<ValidationException>()),
    );
    expect(
      () => PricingService.estimatePurchase(purchase(), 0),
      throwsA(isA<ValidationException>()),
    );
    expect(
      () => PricingService.estimatePurchase(
        purchase(),
        10,
        additionalCostCents: -1,
      ),
      throwsA(isA<ValidationException>()),
    );
  });

  test('latest supplier price and historical minimum remain distinct', () {
    final result = PricingService.comparison(
      product,
      const StoreProfile(defaultMarkupPercent: 20),
      [
        purchase(
          id: 'old-a',
          amount: 14000,
          date: DateTime(2026, 10, 1),
          sequence: 1,
        ),
        purchase(
          id: 'latest-a',
          amount: 16800,
          date: DateTime(2026, 10, 8),
          sequence: 2,
        ),
        purchase(
          id: 'b',
          supplier: supplierB,
          amount: 15600,
          date: DateTime(2026, 10, 5),
          sequence: 3,
        ),
      ],
    );
    expect(result.latestPrices.map((row) => row.purchase.id), [
      'b',
      'latest-a',
    ]);
    expect(result.lowestHistorical!.id, 'old-a');
    expect(
      result.history
          .firstWhere((entry) => entry.purchase.id == 'latest-a')
          .changeCents,
      140,
    );
    expect(
      result.history
          .firstWhere((entry) => entry.purchase.id == 'b')
          .previousCostPerPieceCents,
      isNull,
    );
  });

  test('complete same-day times order by purchase time, not save order', () {
    final result = PricingService.comparison(product, const StoreProfile(), [
      purchase(
        id: 'late',
        amount: 18000,
        date: DateTime(2026, 10, 8, 16),
        hasTime: true,
        sequence: 1,
      ),
      purchase(
        id: 'early',
        amount: 16000,
        date: DateTime(2026, 10, 8, 9),
        hasTime: true,
        sequence: 2,
      ),
    ]);
    expect(result.history.map((entry) => entry.purchase.id), ['early', 'late']);
    expect(result.latestPrices.single.purchase.id, 'late');
    expect(result.history.every((entry) => entry.orderingNote == null), isTrue);
  });

  test('incomplete same-day times explicitly use stable save order', () {
    final result = PricingService.comparison(product, const StoreProfile(), [
      purchase(
        id: 'known-late',
        amount: 18000,
        date: DateTime(2026, 10, 8, 16),
        hasTime: true,
        sequence: 1,
      ),
      purchase(
        id: 'unknown',
        amount: 16000,
        date: DateTime(2026, 10, 8),
        sequence: 2,
      ),
    ]);
    expect(result.history.map((entry) => entry.purchase.id), [
      'known-late',
      'unknown',
    ]);
    expect(result.latestPrices.single.purchase.id, 'unknown');
    expect(
      result.history.every(
        (entry) => entry.orderingNote!.contains('order they were saved'),
      ),
      isTrue,
    );
  });

  test('equal printed times use sequence and expose the tie in history', () {
    final time = DateTime(2026, 10, 8, 9, 30);
    final result = PricingService.comparison(product, const StoreProfile(), [
      purchase(
        id: 'second',
        amount: 18000,
        date: time,
        hasTime: true,
        sequence: 2,
      ),
      purchase(
        id: 'first',
        amount: 16000,
        date: time,
        hasTime: true,
        sequence: 1,
      ),
    ]);
    expect(result.history.map((entry) => entry.purchase.id), [
      'first',
      'second',
    ]);
    expect(
      result.history.every(
        (entry) => entry.orderingNote!.contains('same purchase time'),
      ),
      isTrue,
    );
  });

  test(
    'product zero markup overrides the store default without a truthy check',
    () {
      const zeroMarkup = Product(
        id: 'coffee',
        name: 'Coffee',
        brand: 'Brand X',
        variant: 'Original',
        size: '26g',
        markupPercent: 0,
      );
      final result = PricingService.comparison(
        zeroMarkup,
        const StoreProfile(defaultMarkupPercent: 20),
        [],
      );
      expect(result.effectiveMarkupPercent, 0);
      expect(
        PricingService.comparison(
          product,
          const StoreProfile(),
          [],
        ).effectiveMarkupPercent,
        isNull,
      );
    },
  );

  test(
    'basket chooses whole-pack item subtotal and groups extra cost once',
    () {
      const second = Product(
        id: 'milk',
        name: 'Milk',
        brand: 'Brand Y',
        variant: 'Original',
        size: '33g',
      );
      const unknown = Product(
        id: 'unknown',
        name: 'Unknown price',
        brand: 'Brand Z',
        variant: 'Plain',
        size: '10g',
      );
      final coffeeA = PricingService.estimatePurchase(
        purchase(amount: 10000, quantity: 1, pieces: 100),
        10,
      );
      final coffeeB = PricingService.estimatePurchase(
        purchase(supplier: supplierB, amount: 2000, quantity: 1, pieces: 10),
        10,
      );
      final milkB = PricingService.estimatePurchase(
        purchase(supplier: supplierB, amount: 3000, quantity: 1, pieces: 10),
        10,
      );
      final result = PricingService.basket(
        {
          product: RestockEstimate(
            product: product,
            targetPieces: 10,
            suppliers: [coffeeA, coffeeB],
          ),
          second: RestockEstimate(
            product: second,
            targetPieces: 10,
            suppliers: [milkB],
          ),
          unknown: const RestockEstimate(
            product: unknown,
            targetPieces: 10,
            suppliers: [],
          ),
        },
        additionalCostsCents: {'b': 1000},
      );
      expect(result.groups.single.supplier.id, 'b');
      expect(result.groups.single.items.length, 2);
      expect(result.subtotalCents, 5000);
      expect(result.totalCents, 6000);
      expect(result.missingProducts.single.id, 'unknown');
      expect(
        result.alternatives
            .firstWhere((entry) => entry.supplier.id == 'a')
            .missingProducts
            .map((entry) => entry.id),
        ['milk', 'unknown'],
      );
    },
  );
}
