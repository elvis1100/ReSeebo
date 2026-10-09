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

void main() {
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
