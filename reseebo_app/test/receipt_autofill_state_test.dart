import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/services/receipt_parser.dart';
import 'package:reseebo_app/features/receipt_scan/state/receipt_review_state.dart';
import 'package:reseebo_app/features/receipt_scan/widgets/purchase_date_candidates.dart';

class CatalogAdapter extends MockReseeboDataAdapter {
  @override
  Future<List<ProductMatchSuggestion>> matchAliases(
    String description, {
    String? supplierId,
  }) async => [];
  @override
  Future<List<Product>> getProducts({String? query}) async => const [
    Product(
      id: 'oil',
      name: 'Oil',
      brand: 'UFC',
      variant: 'Golden Fiesta Canola Oil',
      size: '1L',
    ),
  ];
}

class DelayedAliasAdapter extends CatalogAdapter {
  final pending = Completer<List<ProductMatchSuggestion>>();
  @override
  Future<List<ProductMatchSuggestion>> matchAliases(
    String description, {
    String? supplierId,
  }) => pending.future;
}

ReceiptDraft sample() => ReceiptParser().parse(
  imagePath: '/photo.jpg',
  textLines: const [
    OcrTextLine(text: 'Test Grocery'),
    OcrTextLine(text: '08.10.26 16:00'),
    OcrTextLine(text: 'UFC Golden Fiesta Canola Oil 1L'),
    OcrTextLine(text: '1 PC 144.00 144.00 V'),
    OcrTextLine(text: 'TOTAL 144.00'),
  ],
);

class HistoryAdapter extends CatalogAdapter {
  final pending = Completer<ProductComparisonData>();
  @override
  Future<ProductComparisonData> getProductComparison(String productId) =>
      pending.future;
}

ProductComparisonData historyData() => ProductComparisonData(
  product: const Product(
    id: 'oil',
    name: 'Oil',
    brand: 'UFC',
    variant: 'Golden Fiesta Canola Oil',
    size: '1L',
  ),
  profile: const StoreProfile(),
  latestPrices: [],
  lowestHistorical: null,
  history: [
    PriceHistoryRecord(
      purchase: PurchaseRecord(
        id: 'price',
        receiptId: 'receipt',
        productId: 'oil',
        supplier: const Supplier(id: 'store', name: 'Store'),
        purchasedAt: DateTime(2026, 10, 8),
        hasPurchaseTime: false,
        recordedAt: DateTime(2026, 10, 9),
        originalDescription: 'Oil',
        quantity: 1,
        unit: PurchaseUnit.piece,
        piecesPerPack: 1,
        netAmountCents: 1200,
        imagePath: 'photo',
      ),
    ),
  ],
);

void main() {
  test(
    'explicitly confirmed history estimate survives unchanged reload',
    () async {
      final adapter = HistoryAdapter()..pending.complete(historyData());
      final state = ReceiptReviewState(
        adapter: adapter,
        draft: ReceiptDraft(
          lines: [
            ParsedLineItem(
              description: 'UFC Golden Fiesta Canola Oil 1L',
              quantity: 2,
            ),
          ],
        ),
      );
      await state.load();
      final line = state.draft.lines.single;
      state.confirmLine(line);
      expect(line.confirmed, isTrue);
      await state.load();
      expect(line.confirmed, isTrue);
      expect(
        line.provenance[ReceiptSuggestionField.amount]!.origin,
        ReceiptFieldOrigin.history,
      );
      state.dispose();
    },
  );
  test('late alias response preserves explicit cleared product', () async {
    final adapter = DelayedAliasAdapter();
    final state = ReceiptReviewState(adapter: adapter, draft: sample());
    final loading = state.load();
    await Future<void>.delayed(Duration.zero);
    final line = state.draft.lines.single;
    state.setProduct(line, null);
    adapter.pending.complete([
      ProductMatchSuggestion(
        product: (await adapter.getProducts()).single,
        reason: 'Confirmed alias',
        exactAlias: true,
      ),
    ]);
    await loading;
    expect(line.productId, isNull);
    expect(
      line.provenance[ReceiptSuggestionField.product]!.origin,
      ReceiptFieldOrigin.ownerEdited,
    );
    state.dispose();
  });
  test(
    'corrected description refreshes newly matched product history',
    () async {
      final adapter = HistoryAdapter()..pending.complete(historyData());
      final state = ReceiptReviewState(
        adapter: adapter,
        draft: ReceiptDraft(
          lines: [ParsedLineItem(description: 'Unknown oil', quantity: 2)],
        ),
      );
      await state.load();
      final line = state.draft.lines.single;
      expect(line.grossAmountCents, isNull);
      state.editText(
        line,
        ReceiptLineField.description,
        'UFC Golden Fiesta Canola Oil 1L',
      );
      await Future<void>.delayed(Duration.zero);
      expect(line.grossAmountCents, 2400);
      state.dispose();
    },
  );
  test(
    'changing unresolved supplier name invalidates learned aliases',
    () async {
      final adapter = HistoryAdapter()..pending.complete(historyData());
      final state = ReceiptReviewState(
        adapter: adapter,
        draft: ReceiptDraft(
          lines: [
            ParsedLineItem(description: 'UFC Golden Fiesta Canola Oil 1L'),
          ],
        ),
      );
      await state.load();
      final line = state.draft.lines.single;
      line.description = 'OIL';
      line.matchOrigin = 'Previously matched';
      line.confirmed = true;
      state.draft.supplierName = 'Other unresolved store';
      state.changed();
      expect(line.productId, isNull);
      expect(line.grossAmountCents, isNull);
      expect(line.confirmed, isFalse);
      await Future<void>.delayed(Duration.zero);
      state.dispose();
    },
  );
  test('owner_amount_survives_quantity_and_history_refresh', () async {
    final adapter = HistoryAdapter()..pending.complete(historyData());
    final state = ReceiptReviewState(
      adapter: adapter,
      draft: ReceiptDraft(
        lines: [
          ParsedLineItem(
            description: 'UFC Golden Fiesta Canola Oil 1L',
            quantity: 2,
          ),
        ],
      ),
    );
    await state.load();
    final line = state.draft.lines.single;
    expect(line.grossAmountCents, 2400);
    state.editText(line, ReceiptLineField.quantity, '3');
    expect(line.grossAmountCents, 3600);
    state.editText(line, ReceiptLineField.amount, '13.00');
    state.editText(line, ReceiptLineField.quantity, '10');
    await state.load();
    expect(line.grossAmountCents, 1300);
    expect(
      line.provenance[ReceiptSuggestionField.amount]!.origin,
      ReceiptFieldOrigin.ownerEdited,
    );
    state.editText(line, ReceiptLineField.amount, '');
    await state.load();
    expect(line.grossAmountCents, isNull);
    state.dispose();
  });
  test(
    'late history response preserves owner amount and cleared quantity',
    () async {
      final adapter = HistoryAdapter();
      final state = ReceiptReviewState(
        adapter: adapter,
        draft: ReceiptDraft(
          lines: [
            ParsedLineItem(description: 'UFC Golden Fiesta Canola Oil 1L'),
          ],
        ),
      );
      final loading = state.load();
      await Future<void>.delayed(Duration.zero);
      final line = state.draft.lines.single;
      state.editText(line, ReceiptLineField.amount, '13.00');
      state.editText(line, ReceiptLineField.quantity, '');
      adapter.pending.complete(historyData());
      await loading;
      expect(line.grossAmountCents, 1300);
      expect(line.quantity, isNull);
      expect(
        line.provenance[ReceiptSuggestionField.amount]!.origin,
        ReceiptFieldOrigin.ownerEdited,
      );
      expect(line.confirmed, isFalse);
      state.dispose();
    },
  );
  test('disposed review rejects late history suggestions', () async {
    final adapter = HistoryAdapter();
    final state = ReceiptReviewState(
      adapter: adapter,
      draft: ReceiptDraft(
        lines: [ParsedLineItem(description: 'UFC Golden Fiesta Canola Oil 1L')],
      ),
    );
    final loading = state.load();
    await Future<void>.delayed(Duration.zero);
    state.dispose();
    adapter.pending.complete(historyData());
    await loading;
    expect(state.draft.lines.single.grossAmountCents, isNull);
  });
  test(
    'changing supplier invalidates even confirmed supplier-learned matches',
    () async {
      final state = ReceiptReviewState(
        adapter: CatalogAdapter(),
        draft: sample(),
      );
      await state.load();
      final line = state.draft.lines.single;
      line.productId = 'oil';
      line.matchOrigin = 'Previously matched';
      line.confirmed = true;
      state.draft.supplierId = 'different-store';
      state.changed();
      expect(line.productId, isNull);
      expect(line.confirmed, isFalse);
      await Future<void>.delayed(Duration.zero);
      state.dispose();
    },
  );
  test(
    'corrected complete description immediately auto selects catalog item',
    () async {
      final state = ReceiptReviewState(
        adapter: CatalogAdapter(),
        draft: sample(),
      );
      await state.load();
      final line = state.draft.lines.single;
      state.editText(line, ReceiptLineField.description, 'Unclear oil');
      expect(line.productId, isNull);
      state.editText(
        line,
        ReceiptLineField.description,
        'UFCGoldenFiestaCanolaOil1L',
      );
      expect(line.productId, 'oil');
      expect(line.matchOrigin, 'Matched from receipt');
      expect(line.confirmed, isFalse);
      state.dispose();
    },
  );
  test('late alias response cannot replace an owner edit', () async {
    final adapter = DelayedAliasAdapter();
    final state = ReceiptReviewState(adapter: adapter, draft: sample());
    final loading = state.load();
    await Future<void>.delayed(Duration.zero);
    final line = state.draft.lines.single;
    state.editText(line, ReceiptLineField.description, 'UFC Oil 500ml');
    adapter.pending.complete([
      ProductMatchSuggestion(
        product: (await adapter.getProducts()).single,
        reason: 'Previously confirmed',
        exactAlias: true,
      ),
    ]);
    await loading;
    expect(line.description, 'UFC Oil 500ml');
    expect(line.productId, isNull);
    state.dispose();
  });

  test(
    'complete catalog identity prefills; owner edits survive reload',
    () async {
      final state = ReceiptReviewState(
        adapter: CatalogAdapter(),
        draft: sample(),
      );
      await state.load();
      final line = state.draft.lines.single;
      expect(line.productId, 'oil');
      expect(line.matchOrigin, 'Matched from receipt');
      expect(
        line.provenance[ReceiptSuggestionField.product]?.origin,
        ReceiptFieldOrigin.calculated,
      );
      expect(line.confirmed, isFalse);
      state.editText(line, ReceiptLineField.description, 'UFC Oil 500ml');
      state.editText(line, ReceiptLineField.amount, '130');
      await state.load();
      expect(line.productId, isNull);
      expect(line.grossAmountCents, 13000);
      expect(line.amountEdited, isTrue);
      state.dispose();
    },
  );
  test(
    'date choice remembers branch preference without rewriting owner edits',
    () async {
      final adapter = CatalogAdapter();
      await adapter.saveSupplier(
        const Supplier(id: 'test', name: 'Test Grocery', branch: 'Main'),
      );
      final state = ReceiptReviewState(adapter: adapter, draft: sample());
      await state.load();
      expect(state.draft.supplierId, 'test');
      final choice = state.draft.dateCandidates.firstWhere(
        (c) => c.order == NumericDateOrder.dayFirst,
      );
      await state.chooseDateCandidate(choice, remember: true);
      expect(
        (await adapter.getSupplierById('test'))!.dateOrder,
        NumericDateOrder.dayFirst,
      );
      expect(state.draft.purchasedAt, DateTime(2026, 10, 8, 16));
      state.draft.purchasedAt = DateTime(2026, 10, 9);
      await state.load();
      expect(state.draft.purchasedAt, DateTime(2026, 10, 9));
      final next = ReceiptReviewState(adapter: adapter, draft: sample());
      await next.load();
      expect(next.draft.purchasedAt, DateTime(2026, 10, 8, 16));
      expect(next.draft.dateConfirmed, isFalse);
      next.dispose();
      state.dispose();
    },
  );
  test('ambiguous branches cannot lend a date preference', () async {
    final adapter = CatalogAdapter();
    await adapter.saveSupplier(
      const Supplier(
        id: 'a',
        name: 'Test Grocery',
        branch: 'A',
        dateOrder: NumericDateOrder.dayFirst,
      ),
    );
    await adapter.saveSupplier(
      const Supplier(
        id: 'b',
        name: 'Test Grocery',
        branch: 'B',
        dateOrder: NumericDateOrder.monthFirst,
      ),
    );
    final state = ReceiptReviewState(adapter: adapter, draft: sample());
    await state.load();
    expect(state.draft.supplierId, isNull);
    expect(state.draft.purchasedAt, isNull);
    expect(state.draft.dateCandidates, hasLength(2));
    state.dispose();
  });
  testWidgets('date candidates show explicit dates and remember opt-in', (
    tester,
  ) async {
    PurchaseDateCandidate? selected;
    bool? remembered;
    final candidate = PurchaseDateCandidate(
      DateTime(2026, 10, 8, 16),
      NumericDateOrder.dayFirst,
      true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PurchaseDateCandidates(
            candidates: [candidate],
            canRemember: true,
            enabled: true,
            onChoose: (value, remember) async {
              selected = value;
              remembered = remember;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(selected, candidate);
    expect(remembered, isTrue);
  });
}
