import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/services/receipt_parser.dart';
import 'package:reseebo_app/core/services/receipt_suggestion_service.dart';

const coffee = Product(
  id: 'coffee',
  name: 'Coffee',
  brand: 'Brand X',
  variant: 'Original',
  size: '26g',
);
const supplier = Supplier(id: 'store', name: 'Store');
PurchaseRecord purchase({
  String id = 'old',
  Supplier source = supplier,
  int cents = 1200,
  int quantity = 1,
  int pieces = 1,
  int sequence = 1,
  bool timed = true,
  DateTime? date,
  DateTime? recorded,
}) => PurchaseRecord(
  id: id,
  receiptId: 'receipt-$id',
  productId: 'coffee',
  supplier: source,
  purchasedAt: date ?? DateTime(2026, 10, 8, 16),
  hasPurchaseTime: timed,
  recordedAt: recorded ?? DateTime(2026, 10, 9),
  originalDescription: 'Brand X Original 26g',
  quantity: quantity,
  unit: pieces == 1 ? PurchaseUnit.piece : PurchaseUnit.pack,
  piecesPerPack: pieces,
  netAmountCents: cents,
  imagePath: 'photo',
  sequence: sequence,
);
ReceiptDraft suggest(
  ReceiptDraft draft, {
  List<Product> products = const [coffee],
  List<PurchaseRecord> history = const [],
}) => ReceiptSuggestionService().suggest(
  draft,
  products: products,
  confirmedHistory: history,
  importedAt: DateTime(2026, 10, 10, 20),
);
ParsedLineItem item({
  int? quantity = 2,
  PurchaseUnit? unit = PurchaseUnit.piece,
  int? pieces = 1,
}) => ParsedLineItem(
  description: 'Brand X Original 26g',
  quantity: quantity,
  unit: unit,
  piecesPerPack: pieces,
);

ReceiptDraft explicitUnitPriceDraft(String row) => ReceiptParser().parse(
  imagePath: 'photo',
  textLines: [
    const OcrTextLine(text: 'Store'),
    OcrTextLine(text: row),
  ],
);

void main() {
  test('normalized and active discounts share bounded exact arithmetic', () {
    final draft = explicitUnitPriceDraft('2 Coffee 26G @21');
    draft.lines.single.normalizedDiscountCents = 600;
    draft.lines.single.discountCents = 400;
    final line = suggest(draft).lines.single;
    expect(line.grossAmountCents, 3600);
    expect(line.netAmountCents, 3200);
    expect(line.snapshot().normalizedDiscountCents, 600);
    expect(
      line.provenance[ReceiptSuggestionField.amount]!.explanation,
      contains('1000'),
    );
    expect(
      suggest(ReceiptDraft(lines: [line])).lines.single.netAmountCents,
      3200,
    );
    for (final normalized in [-1, 4200, maxAmountCents + 1]) {
      final invalid = explicitUnitPriceDraft('2 Coffee 26G @21');
      invalid.lines.single.normalizedDiscountCents = normalized;
      final result = suggest(invalid);
      expect(
        result.lines.single.grossAmountCents,
        isNull,
        reason: 'normalized $normalized',
      );
      expect(result.detectedTotalCents, isNull);
    }
    draft.lines.single.normalizedDiscountCents = maxAmountCents;
    draft.lines.single.discountCents = 1;
    expect(suggest(draft).lines.single.grossAmountCents, isNull);
  });
  test(
    'explicit calculated price provenance records the applied discount without owner edits',
    () {
      final draft = explicitUnitPriceDraft('2 Coffee 26G @21');
      draft.lines.single.discountCents = 1000;
      final result = suggest(draft);
      final line = result.lines.single;
      expect(line.grossAmountCents, 4200);
      expect(line.netAmountCents, 3200);
      expect(line.extractedUnitPriceCents, 2100);
      expect(line.amountEdited, isFalse);
      expect(
        line.provenance[ReceiptSuggestionField.amount]!.origin,
        ReceiptFieldOrigin.calculated,
      );
      expect(
        line.provenance[ReceiptSuggestionField.amount]!.explanation,
        contains('1000'),
      );
    },
  );
  test(
    'explicit receipt unit price precedes history and retains raw missing-total baseline',
    () {
      for (final history in <List<PurchaseRecord>>[
        [],
        [purchase(cents: 2200)],
      ]) {
        final draft = explicitUnitPriceDraft('2 Coffee 26G @21');
        final before = draft.rawText;
        expect(draft.lines.single.quantity, 2);
        expect(draft.lines.single.grossAmountCents, isNull);
        expect(draft.lines.single.extractedUnitPriceCents, 2100);
        final product = const Product(
          id: 'coffee',
          name: 'Coffee',
          brand: 'Coffee',
          variant: '',
          size: '26g',
          nameOnly: true,
        );
        final result = suggest(draft, products: [product], history: history);
        expect(result.lines.single.productId, 'coffee');
        expect(result.lines.single.grossAmountCents, 4200);
        expect(result.lines.single.extractedAmountCents, isNull);
        expect(
          result.lines.single.provenance[ReceiptSuggestionField.amount]!.origin,
          ReceiptFieldOrigin.calculated,
        );
        expect(result.lines.single.confirmed, isFalse);
        expect(result.rawText, before);
        expect(result.snapshot().lines.single.extractedUnitPriceCents, 2100);
      }
    },
  );
  test('explicit decimal unit price is not promoted to raw line total', () {
    final draft = explicitUnitPriceDraft('2 Coffee 26G @21.00');
    expect(draft.lines.single.grossAmountCents, isNull);
    expect(draft.lines.single.extractedUnitPriceCents, 2100);
    expect(suggest(draft).lines.single.grossAmountCents, 4200);
  });
  test(
    'calculated receipt amount recomputes quantity without replacing owner amounts or clears',
    () {
      final first = suggest(explicitUnitPriceDraft('2 Coffee 26G @21'));
      first.lines.single.confirmed = true;
      final same = suggest(first);
      expect(same.lines.single.confirmed, isTrue);
      same.lines.single.quantity = 3;
      same.lines.single.quantityEdited = true;
      final changed = suggest(same);
      expect(changed.lines.single.grossAmountCents, 6300);
      expect(changed.lines.single.confirmed, isFalse);
      changed.lines.single.grossAmountCents = 1300;
      changed.lines.single.amountEdited = true;
      expect(suggest(changed).lines.single.grossAmountCents, 1300);
      changed.lines.single.grossAmountCents = null;
      expect(suggest(changed).lines.single.grossAmountCents, isNull);
      first.lines.single.quantity = null;
      first.lines.single.quantityEdited = true;
      expect(suggest(first).lines.single.grossAmountCents, isNull);
    },
  );
  test(
    'explicit price cannot resolve competing prices damaged totals or fractional weights',
    () {
      for (final row in [
        '2 Coffee 26G @21 @22',
        '2 Coffee 26G @21 50.00',
        '2 Coffee 26G @21 50.,00',
        'Rice 0.50 KG @21',
      ]) {
        final result = suggest(
          explicitUnitPriceDraft(row),
          products: const [
            Product(
              id: 'coffee',
              name: 'Coffee',
              brand: 'Coffee',
              variant: '',
              size: '26g',
              nameOnly: true,
            ),
          ],
          history: [purchase(cents: 2200)],
        );
        expect(result.lines.single.grossAmountCents, isNull, reason: row);
        expect(result.lines.single.costPerPieceCents, isNull, reason: row);
      }
    },
  );
  test(
    'explicit pack unit price calculates payable amount without fabricating pack contents',
    () {
      final result = suggest(explicitUnitPriceDraft('2 packs Coffee 26G @21'));
      expect(result.lines.single.grossAmountCents, 4200);
      expect(result.lines.single.piecesPerPack, isNull);
      expect(result.lines.single.costPerPieceCents, isNull);
    },
  );
  test(
    'owner confirmation survives identical history proposal but changes invalidate it',
    () {
      final first = suggest(
        ReceiptDraft(lines: [item()]),
        history: [purchase()],
      );
      first.lines.single.confirmed = true;
      final unchanged = suggest(first, history: [purchase()]);
      expect(unchanged.lines.single.confirmed, isTrue);
      expect(
        unchanged
            .lines
            .single
            .provenance[ReceiptSuggestionField.amount]!
            .origin,
        ReceiptFieldOrigin.history,
      );
      final changedPrice = suggest(unchanged, history: [purchase(cents: 1500)]);
      expect(changedPrice.lines.single.confirmed, isFalse);
      unchanged.lines.single.confirmed = true;
      final changedSource = suggest(
        unchanged,
        history: [purchase(id: 'different')],
      );
      expect(changedSource.lines.single.confirmed, isFalse);
    },
  );
  test(
    'fractional gram weight and fractional printed piece count stay unresolved',
    () {
      for (final text in [
        'Rice 0.50 g 30.00',
        '2.50 pcs Brand X Original 26g 30.00',
      ]) {
        final draft = ReceiptParser().parse(
          imagePath: 'photo',
          textLines: [
            const OcrTextLine(text: 'Store'),
            OcrTextLine(text: text),
          ],
        );
        final result = suggest(draft, history: [purchase()]);
        expect(result.lines.single.quantity, isNull, reason: text);
        expect(result.lines.single.unit, isNull, reason: text);
        expect(result.lines.single.costPerPieceCents, isNull, reason: text);
      }
    },
  );
  test(
    'same supplier historical price scales once and retains source provenance',
    () {
      final result = suggest(
        ReceiptDraft(supplierId: 'store', lines: [item()]),
        history: [
          purchase(),
          purchase(
            id: 'new',
            source: const Supplier(id: 'other', name: 'Other'),
            cents: 1500,
            date: DateTime(2026, 10, 10),
          ),
        ],
      );
      final line = result.lines.single;
      expect(line.productId, 'coffee');
      expect(line.grossAmountCents, 2400);
      expect(line.confirmed, isFalse);
      final origin = line.provenance[ReceiptSuggestionField.amount]!;
      expect(origin.origin, ReceiptFieldOrigin.history);
      expect(origin.sourcePurchaseId, 'old');
      expect(origin.sourceReceiptId, 'receipt-old');
      expect(origin.sourceSupplierId, 'store');
      expect(origin.sourcePurchasedAt, DateTime(2026, 10, 8, 16));
    },
  );
  test('two matching catalog sizes produce no historical price', () {
    final result = suggest(
      ReceiptDraft(
        lines: [
          ParsedLineItem(
            description: 'Brand X Original',
            quantity: 2,
            unit: PurchaseUnit.piece,
          ),
        ],
      ),
      products: [
        coffee,
        coffee.copyWith(id: 'large', size: '50g'),
      ],
      history: [purchase()],
    );
    expect(result.lines.single.productId, isNull);
    expect(result.lines.single.grossAmountCents, isNull);
  });
  test('unknown pack denominator never produces a usable piece cost', () {
    final result = suggest(
      ReceiptDraft(lines: [item(unit: PurchaseUnit.pack, pieces: null)]),
      history: [purchase()],
    );
    expect(result.lines.single.piecesPerPack, isNull);
    expect(result.lines.single.grossAmountCents, isNull);
    expect(result.lines.single.costPerPieceCents, isNull);
  });
  test('fractional weight never receives counted defaults', () {
    final result = suggest(
      ReceiptDraft(
        rawText: 'Rice 0.50 KG 30.00',
        lines: [
          ParsedLineItem(description: 'Rice 0.50 KG', grossAmountCents: 3000),
        ],
      ),
    );
    expect(result.lines.single.quantity, isNull);
    expect(result.lines.single.unit, isNull);
    expect(result.lines.single.costPerPieceCents, isNull);
  });
  test('missing count suggests one piece with assumed origin', () {
    final result = suggest(
      ReceiptDraft(lines: [item(quantity: null, unit: null, pieces: null)]),
    );
    final line = result.lines.single;
    expect(line.quantity, 1);
    expect(line.unit, PurchaseUnit.piece);
    expect(
      line.provenance[ReceiptSuggestionField.quantity]!.origin,
      ReceiptFieldOrigin.assumed,
    );
    expect(
      line.provenance[ReceiptSuggestionField.unit]!.origin,
      ReceiptFieldOrigin.assumed,
    );
    expect(line.confirmed, isFalse);
  });
  test('known receipt total never allocates an unsupported missing price', () {
    final result = suggest(
      ReceiptDraft(detectedTotalCents: 9999, lines: [item()]),
    );
    expect(result.lines.single.grossAmountCents, isNull);
    expect(result.detectedTotalCents, 9999);
  });
  test('owner_amount_survives_quantity_and_history_refresh', () {
    final line = item()
      ..grossAmountCents = 1300
      ..amountEdited = true;
    line.provenance[ReceiptSuggestionField.amount] =
        const ReceiptFieldProvenance(
          origin: ReceiptFieldOrigin.ownerEdited,
          explanation: 'Owner entered amount.',
        );
    final first = suggest(ReceiptDraft(lines: [line]), history: [purchase()]);
    first.lines.single.quantity = 10;
    final result = suggest(first, history: [purchase(cents: 1500)]);
    expect(result.lines.single.grossAmountCents, 1300);
  });
  test('manual clears stay empty during suggestion refresh', () {
    final line = item()
      ..quantity = null
      ..quantityEdited = true
      ..amountEdited = true;
    final result = suggest(ReceiptDraft(lines: [line]), history: [purchase()]);
    expect(result.lines.single.quantity, isNull);
    expect(result.lines.single.grossAmountCents, isNull);
  });
  test('contradictory_printed_prices_remain_candidates', () {
    final draft = ReceiptParser().parse(
      imagePath: 'photo',
      textLines: const [
        OcrTextLine(text: 'Store'),
        OcrTextLine(text: '2 pcs Brand X Original 26g 12.00 30.00'),
        OcrTextLine(text: 'TOTAL 30.00'),
      ],
    );
    final result = suggest(draft, history: [purchase()]);
    expect(result.lines.single.grossAmountCents, isNull);
    expect(result.lines.single.warnings, contains(contains('Multiple prices')));
    expect(result.rawText, contains('12.00 30.00'));
  });
  test('ambiguous_date_keeps_candidates', () {
    final draft = ReceiptParser().parse(
      imagePath: 'photo',
      textLines: const [
        OcrTextLine(text: 'Store'),
        OcrTextLine(text: '08.10.26 16:00'),
      ],
    );
    final result = suggest(draft);
    expect(result.purchasedAt, isNull);
    expect(result.dateCandidates, hasLength(2));
    expect(result.dateConfirmed, isFalse);
  });
  test('import date is assumed and never confirmed', () {
    final result = suggest(ReceiptDraft());
    expect(result.purchasedAt, DateTime(2026, 10, 10));
    expect(result.hasPurchaseTime, isFalse);
    expect(result.dateConfirmed, isFalse);
    expect(
      result.provenance[ReceiptMetadataField.purchasedAt]!.origin,
      ReceiptFieldOrigin.assumed,
    );
  });
  test('incomplete calculated totals are explicitly partial', () {
    final result = suggest(
      ReceiptDraft(
        lines: [
          item()..grossAmountCents = 1200,
          ParsedLineItem(description: 'Unknown'),
        ],
      ),
    );
    expect(result.detectedTotalCents, 1200);
    expect(result.totalIsPartial, isTrue);
    expect(
      result.provenance[ReceiptMetadataField.total]!.origin,
      ReceiptFieldOrigin.calculated,
    );
    expect(
      result.provenance[ReceiptMetadataField.total]!.explanation,
      contains('Partial'),
    );
  });
  test('raw_evidence_is_byte_for_byte_unchanged', () {
    final draft = ReceiptParser().parse(
      imagePath: 'photo',
      textLines: const [
        OcrTextLine(text: ' Store  '),
        OcrTextLine(
          text: 'Brand X Original 26g',
          tokens: [OcrTextToken(text: 'Original', left: 42)],
        ),
      ],
    );
    final raw = draft.rawText;
    final result = suggest(draft, history: [purchase()]);
    expect(result.rawText, raw);
    expect(result.textLines.first.text, ' Store  ');
    expect(result.textLines.last.tokens.single.left, 42);
    expect(draft.lines.single.quantity, isNull);
    result.lines.single.provenance.clear();
    expect(draft.lines.single.provenance, isEmpty);
  });
  test(
    'same day missing times follow saved sequence even with corrected clock',
    () {
      final result = suggest(
        ReceiptDraft(supplierId: 'store', lines: [item()]),
        history: [
          purchase(
            id: 'first',
            cents: 1200,
            sequence: 1,
            recorded: DateTime(2026, 10, 10),
            date: DateTime(2026, 10, 8, 23),
          ),
          purchase(
            id: 'second',
            cents: 1500,
            sequence: 2,
            timed: false,
            recorded: DateTime(2026, 10, 9),
            date: DateTime(2026, 10, 8),
          ),
        ],
      );
      expect(result.lines.single.grossAmountCents, 3000);
      expect(
        result
            .lines
            .single
            .provenance[ReceiptSuggestionField.amount]!
            .sourcePurchaseId,
        'second',
      );
    },
  );
  test('fractional centavos round only after scaling total pieces', () {
    final result = suggest(
      ReceiptDraft(lines: [item(quantity: 3)]),
      history: [purchase(cents: 100, quantity: 3)],
    );
    expect(result.lines.single.grossAmountCents, 100);
  });
  test('history estimate refresh does not become receipt evidence', () {
    final first = suggest(ReceiptDraft(lines: [item()]), history: [purchase()]);
    first.lines.single.quantity = 3;
    final second = suggest(first, history: [purchase()]);
    expect(second.lines.single.grossAmountCents, 3600);
    expect(second.lines.single.extractedAmountCents, isNull);
  });
}
