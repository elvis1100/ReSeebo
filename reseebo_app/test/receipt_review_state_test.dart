import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/features/receipt_scan/state/receipt_review_state.dart';

void main() {
  test(
    'invalid discount hides the draft total instead of adding a centavo',
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
        ReceiptLineField.discount,
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
  test('multiple amounts and tax suffixes require manual correction', () {
    final state = ReceiptReviewState(
      adapter: MockReseeboDataAdapter(),
      draft: ReceiptDraft(
        lines: [
          ParsedLineItem(
            description: 'Coffee',
            grossAmountCents: 16800,
            confirmed: true,
          ),
        ],
      ),
    );
    final line = state.draft.lines.single;
    state.selectTarget(line.id, ReceiptLineField.amount);
    for (final text in ['84.00 168.00', '168.00V', '168.OO', '-168.00']) {
      expect(state.assignText(text), isNotNull, reason: text);
      expect(line.grossAmountCents, 16800);
      expect(line.confirmed, isTrue);
    }
    state.dispose();
  });
  test(
    'page switching clears token selection and keeps recognition provenance',
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
      state.selectTarget(
        state.draft.lines.single.id,
        ReceiptLineField.quantity,
      );
      expect(state.selectedPage, 1);
      expect(state.pages[state.selectedPage].recognitionImagePath, 'rotated-b');
      state.toggleToken(0);
      expect(state.selectedText, '10');
      state.selectPage(0);
      expect(state.selectedText, isEmpty);
      expect(state.pages[state.selectedPage].recognitionImagePath, 'cropped-a');
      state.toggleToken(0);
      expect(state.assignText(state.selectedText), isNull);
      expect(state.draft.lines.single.quantity, 2);
      state.dispose();
    },
  );

  test(
    'description assignment removes stale product identity and confirmation',
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
      state.selectTarget(line.id, ReceiptLineField.description);
      expect(state.assignText('Brand X Original 26g'), isNull);
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
          ParsedLineItem(description: 'Coffee', quantity: 2, confirmed: true),
        ],
      ),
    );
    final line = state.draft.lines.single;
    state.editText(line, ReceiptLineField.quantity, '2.5');
    expect(line.quantity, isNull);
    expect(line.confirmed, isFalse);
    state.dispose();
  });

  test(
    'removing the assignment target clears it and leaves other rows intact',
    () {
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
      state.selectTarget(removed.id, ReceiptLineField.quantity);
      state.removeLine(removed);
      expect(state.targetLineId, isNull);
      expect(state.assignText('8'), isNotNull);
      expect(state.draft.lines.single.quantity, 12);
      state.dispose();
    },
  );
  test('invalid purchase cannot be confirmed', () {
    final state = ReceiptReviewState(
      adapter: MockReseeboDataAdapter(),
      draft: ReceiptDraft(lines: [ParsedLineItem(description: 'Coffee')]),
    );
    state.confirmLine(state.draft.lines.single);
    expect(state.draft.lines.single.confirmed, isFalse);
    state.dispose();
  });

  test('assignment clears confirmation and total acknowledgement', () {
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
    state.selectTarget(line.id, ReceiptLineField.amount);
    expect(state.assignText('168.00'), isNull);
    expect(line.grossAmountCents, 16800);
    expect(line.confirmed, isFalse);
    expect(state.draft.totalDifferenceConfirmed, isFalse);
    expect(source.grossAmountCents, 16000);
    state.dispose();
  });

  test('ambiguous quantity leaves existing value and confirmation intact', () {
    final state = ReceiptReviewState(
      adapter: MockReseeboDataAdapter(),
      draft: ReceiptDraft(
        lines: [
          ParsedLineItem(description: 'Coffee', quantity: 2, confirmed: true),
        ],
      ),
    );
    final line = state.draft.lines.single;
    state.selectTarget(line.id, ReceiptLineField.quantity);
    for (final text in ['2 10', '2.5', 'O2', '2 pcs', '0', '1000001']) {
      expect(state.assignText(text), isNotNull, reason: text);
      expect(line.quantity, 2);
      expect(line.confirmed, isTrue);
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
