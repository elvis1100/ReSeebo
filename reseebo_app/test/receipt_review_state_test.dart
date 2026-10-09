import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/features/receipt_scan/state/receipt_review_state.dart';

void main() {
  test(
    'unique saved supplier and alias prefill without confirming purchases',
    () async {
      final state = ReceiptReviewState(
        adapter: _AutofillAdapter(),
        draft: ReceiptDraft(
          supplierName: ' Grocery Store ',
          lines: [ParsedLineItem(description: 'BRANDX COF 26G')],
        ),
      );
      await state.load();
      expect(state.draft.supplierId, 'supplier');
      expect(state.draft.supplierBranch, 'Main');
      expect(state.draft.lines.single.productId, 'coffee');
      expect(state.draft.lines.single.confirmed, isFalse);
      state.dispose();
    },
  );

  test(
    'ambiguous saved aliases do not choose a product automatically',
    () async {
      final state = ReceiptReviewState(
        adapter: _AutofillAdapter(ambiguous: true),
        draft: ReceiptDraft(lines: [ParsedLineItem(description: 'COFFEE')]),
      );
      await state.load();
      expect(state.draft.lines.single.productId, isNull);
      state.dispose();
    },
  );

  test(
    'new review and manually added items default to pieces without confirmation',
    () {
      final original = ParsedLineItem(description: 'Coffee');
      final state = ReceiptReviewState(
        adapter: MockReseeboDataAdapter(),
        draft: ReceiptDraft(lines: [original]),
      );
      expect(state.draft.lines.single.unit, PurchaseUnit.piece);
      expect(state.draft.lines.single.piecesPerPack, 1);
      expect(state.draft.lines.single.confirmed, isFalse);
      expect(original.unit, isNull);
      state.addLine();
      expect(state.draft.lines.last.unit, PurchaseUnit.piece);
      expect(state.draft.lines.last.piecesPerPack, 1);
      state.dispose();
    },
  );

  test(
    'review retains net amount of older drafts without a second deduction',
    () {
      final original = ParsedLineItem(
        description: 'Coffee',
        grossAmountCents: 2000,
        discountCents: 200,
        unit: PurchaseUnit.pack,
        piecesPerPack: 10,
      );
      final state = ReceiptReviewState(
        adapter: MockReseeboDataAdapter(),
        draft: ReceiptDraft(lines: [original]),
      );
      expect(state.draft.lines.single.grossAmountCents, 1800);
      expect(state.draft.lines.single.discountCents, 0);
      expect(state.draft.lines.single.unit, PurchaseUnit.pack);
      expect(state.draft.lines.single.piecesPerPack, 10);
      expect(state.lineTotalCents, 1800);
      expect(original.discountCents, 200);
      state.dispose();
    },
  );

  test(
    'invalid amount hides the draft total instead of retaining an old value',
    () {
      final state = ReceiptReviewState(
        adapter: MockReseeboDataAdapter(),
        draft: ReceiptDraft(
          lines: [
            ParsedLineItem(description: 'Coffee', grossAmountCents: 16800),
          ],
        ),
      );
      state.editText(
        state.draft.lines.single,
        ReceiptLineField.amount,
        'eight',
      );
      expect(state.lineTotalCents, isNull);
      state.dispose();
    },
  );

  test('adding or removing a row invalidates previous duplicate consent', () {
    final state = ReceiptReviewState(
      adapter: MockReseeboDataAdapter(),
      draft: ReceiptDraft(
        allowDuplicate: true,
        lines: [ParsedLineItem(description: 'Coffee')],
      ),
    );
    state.addLine();
    expect(state.draft.allowDuplicate, isFalse);
    state.draft.allowDuplicate = true;
    state.removeLine(state.draft.lines.last);
    expect(state.draft.allowDuplicate, isFalse);
    state.dispose();
  });
  test('invalid manual amounts clear stale values and confirmation', () {
    final state = ReceiptReviewState(
      adapter: MockReseeboDataAdapter(),
      draft: ReceiptDraft(
        lines: [
          ParsedLineItem(
            description: 'Coffee',
            grossAmountCents: 16800,
            unit: PurchaseUnit.piece,
            piecesPerPack: 1,
            confirmed: true,
          ),
        ],
      ),
    );
    final line = state.draft.lines.single;
    for (final text in ['84.00 168.00', '168.00V', '168.OO', '-168.00']) {
      state.editText(line, ReceiptLineField.amount, text);
      expect(line.grossAmountCents, isNull, reason: text);
      expect(line.confirmed, isFalse);
    }
    state.dispose();
  });
  test(
    'page switching retains read-only original and recognition provenance',
    () {
      final state = ReceiptReviewState(
        adapter: MockReseeboDataAdapter(),
        draft: ReceiptDraft(
          imagePaths: ['original-a', 'original-b'],
          ocrPages: [
            const ReceiptOcrPage(
              imagePath: 'original-a',
              recognitionImagePath: 'cropped-a',
              textLines: [
                OcrTextLine(
                  text: '2',
                  tokens: [OcrTextToken(text: '2')],
                ),
              ],
            ),
            const ReceiptOcrPage(
              imagePath: 'original-b',
              recognitionImagePath: 'rotated-b',
              textLines: [
                OcrTextLine(
                  text: '10',
                  tokens: [OcrTextToken(text: '10')],
                ),
              ],
            ),
          ],
          lines: [ParsedLineItem(description: 'Coffee', sourcePage: 1)],
        ),
      );
      state.selectPage(1);
      expect(state.selectedPage, 1);
      expect(state.pages[state.selectedPage].imagePath, 'original-b');
      expect(state.pages[state.selectedPage].recognitionImagePath, 'rotated-b');
      state.selectPage(0);
      expect(state.pages[state.selectedPage].imagePath, 'original-a');
      expect(state.pages[state.selectedPage].recognitionImagePath, 'cropped-a');
      expect(
        state.pages[state.selectedPage].textLines.single.tokens.single.text,
        '2',
      );
      expect(state.draft.lines.single.quantity, isNull);
      state.dispose();
    },
  );

  test(
    'manual description edits remove stale product identity and confirmation',
    () {
      final state = ReceiptReviewState(
        adapter: MockReseeboDataAdapter(),
        draft: ReceiptDraft(
          lines: [
            ParsedLineItem(
              description: 'Old Coffee',
              productId: 'old',
              confirmed: true,
            ),
          ],
        ),
      );
      final line = state.draft.lines.single;
      state.editText(
        line,
        ReceiptLineField.description,
        'Brand X Original 26g',
      );
      expect(line.description, 'Brand X Original 26g');
      expect(line.productId, isNull);
      expect(line.confirmed, isFalse);
      state.dispose();
    },
  );

  test('invalid manual number cannot retain an old confirmed quantity', () {
    final state = ReceiptReviewState(
      adapter: MockReseeboDataAdapter(),
      draft: ReceiptDraft(
        lines: [
          ParsedLineItem(
            description: 'Coffee',
            quantity: 2,
            unit: PurchaseUnit.piece,
            piecesPerPack: 1,
            confirmed: true,
          ),
        ],
      ),
    );
    final line = state.draft.lines.single;
    state.editText(line, ReceiptLineField.quantity, '2.5');
    expect(line.quantity, isNull);
    expect(line.confirmed, isFalse);
    state.dispose();
  });

  test('removing a line leaves unrelated rows intact', () {
    final state = ReceiptReviewState(
      adapter: MockReseeboDataAdapter(),
      draft: ReceiptDraft(
        lines: [
          ParsedLineItem(description: 'Coffee', quantity: 2),
          ParsedLineItem(description: 'Milk', quantity: 12),
        ],
      ),
    );
    final removed = state.draft.lines.first;
    state.removeLine(removed);
    expect(state.draft.lines.single.quantity, 12);
    state.dispose();
  });
  test('invalid purchase cannot be confirmed', () {
    final state = ReceiptReviewState(
      adapter: MockReseeboDataAdapter(),
      draft: ReceiptDraft(lines: [ParsedLineItem(description: 'Coffee')]),
    );
    state.confirmLine(state.draft.lines.single);
    expect(state.draft.lines.single.confirmed, isFalse);
    state.dispose();
  });

  test('manual amount edit clears confirmation and total acknowledgement', () {
    final source = ParsedLineItem(
      description: 'Coffee',
      quantity: 2,
      unit: PurchaseUnit.pack,
      piecesPerPack: 10,
      grossAmountCents: 16000,
      confirmed: true,
    );
    final state = ReceiptReviewState(
      adapter: MockReseeboDataAdapter(),
      draft: ReceiptDraft(lines: [source], totalDifferenceConfirmed: true),
    );
    final line = state.draft.lines.single;
    state.editText(line, ReceiptLineField.amount, '168.00');
    expect(line.grossAmountCents, 16800);
    expect(line.confirmed, isFalse);
    expect(state.draft.totalDifferenceConfirmed, isFalse);
    expect(source.grossAmountCents, 16000);
    state.dispose();
  });

  test('ambiguous manual quantities clear stale values and confirmation', () {
    final state = ReceiptReviewState(
      adapter: MockReseeboDataAdapter(),
      draft: ReceiptDraft(
        lines: [
          ParsedLineItem(
            description: 'Coffee',
            quantity: 2,
            unit: PurchaseUnit.piece,
            piecesPerPack: 1,
            confirmed: true,
          ),
        ],
      ),
    );
    final line = state.draft.lines.single;
    for (final text in ['2 10', '2.5', 'O2', '2 pcs', '0', '1000001']) {
      state.editText(line, ReceiptLineField.quantity, text);
      expect(line.quantity, isNull, reason: text);
      expect(line.confirmed, isFalse);
    }
    state.dispose();
  });

  test('pieces toggle sets one per unit and packs keeps contents unknown', () {
    final state = ReceiptReviewState(
      adapter: MockReseeboDataAdapter(),
      draft: ReceiptDraft(
        lines: [
          ParsedLineItem(
            description: 'Coffee',
            unit: PurchaseUnit.pack,
            piecesPerPack: 10,
            confirmed: true,
          ),
        ],
      ),
    );
    final line = state.draft.lines.single;
    state.setUnit(line, PurchaseUnit.piece);
    expect(line.piecesPerPack, 1);
    expect(line.confirmed, isFalse);
    state.setUnit(line, PurchaseUnit.pack);
    expect(line.piecesPerPack, isNull);
    state.dispose();
  });
}

class _AutofillAdapter extends MockReseeboDataAdapter {
  _AutofillAdapter({this.ambiguous = false});
  final bool ambiguous;
  static const coffee = Product(
    id: 'coffee',
    name: 'Coffee',
    brand: 'Brand X',
    variant: 'Original',
    size: '26g',
  );
  static const largeCoffee = Product(
    id: 'large',
    name: 'Coffee',
    brand: 'Brand X',
    variant: 'Original',
    size: '50g',
  );
  @override
  Future<List<Product>> getProducts({String? query}) async => [
    coffee,
    largeCoffee,
  ];
  @override
  Future<List<Supplier>> getSuppliers() async => [
    const Supplier(id: 'supplier', name: 'Grocery Store', branch: 'Main'),
  ];
  @override
  Future<List<ProductMatchSuggestion>> matchAliases(String description) async =>
      [
        const ProductMatchSuggestion(
          product: coffee,
          reason: 'Saved description',
          exactAlias: true,
        ),
        if (ambiguous)
          const ProductMatchSuggestion(
            product: largeCoffee,
            reason: 'Saved description',
            exactAlias: true,
          ),
      ];
}
