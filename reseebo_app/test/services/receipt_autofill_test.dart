import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/services/receipt_parser.dart';
import 'package:reseebo_app/core/services/receipt_purchase_datetime.dart';
import 'package:reseebo_app/core/services/exact_product_match.dart';

ReceiptDraft parse(List<String> rows) => ReceiptParser().parse(
  imagePath: '/receipt.jpg',
  textLines: [for (final text in rows) OcrTextLine(text: text)],
);

void main() {
  test('name cleanup keeps fractional sizes and strips damaged money only', () {
    final draft = parse([
      'STORE',
      'IceDream Ube Cheese 1.5L 169.75 V',
      '1 Choco Mucho 130G @10.25 10.,25',
      '2 Coffee 26G @21',
    ]);
    expect(draft.lines[0].description, 'IceDream Ube Cheese 1.5L');
    expect(draft.lines[1].description, 'Choco Mucho 130G');
    expect(draft.lines[1].quantity, 1);
    expect(draft.lines[1].grossAmountCents, isNull);
    expect(draft.lines[2].description, 'Coffee 26G');
    expect(draft.lines[2].grossAmountCents, isNull);
    expect(draft.rawText, contains('10.,25'));
  });
  test('unlabeled trailing numerals remain identity despite agreeing prices', () {
    final draft = parse([
      'STORE',
      'Noodles 85g 2',
      '18.50 37.00 V',
      'Coffee 26g 3',
      '22.00 65.00 V',
      'Onions 0.622KIL',
      '290.00 180.38 E',
    ]);
    expect(draft.lines.first.description, 'Noodles 85g 2');
    expect(draft.lines.first.quantity, isNull);
    expect(draft.lines.first.grossAmountCents, isNull);
    expect(draft.lines.first.unit, isNull);
    expect(
      draft.lines.first.warnings.any(
        (warning) => warning.contains('Multiple prices'),
      ),
      isTrue,
    );
    expect(draft.lines[1].description, 'Coffee 26g 3');
    expect(draft.lines[1].quantity, isNull);
    expect(draft.lines[1].grossAmountCents, isNull);
    expect(draft.lines.every((line) => line.quantity == null), isTrue);
  });
  test('quantity header identifies trailing count in a wrapped price pair', () {
    final draft = parse([
      'STORE',
      'DESCRIPTION QTY PRICE AMOUNT',
      'Noodles 85g 2',
      '18.50 37.00 V',
    ]);
    expect(draft.lines.single.description, 'Noodles 85g');
    expect(draft.lines.single.quantity, 2);
    expect(draft.lines.single.grossAmountCents, 3700);
    expect(draft.lines.single.unit, isNull);
  });
  test('unmarked price pair resolves only with exact quantity arithmetic', () {
    final draft = parse([
      'STORE',
      '2 Tang Mango 19g 20.50 41.00',
      '3 pcs Coffee 26g 22.00 66.00',
      '2 Milk 1L 20.50 40.00',
      '7 UP 1L 20.50 143.50',
      'TOTAL 394.00',
    ]);
    expect(draft.lines.map((line) => line.quantity), [2, 3, 2, null]);
    expect(draft.lines.map((line) => line.grossAmountCents), [
      4100,
      6600,
      null,
      null,
    ]);
    expect(draft.lines.take(3).map((line) => line.description), [
      'Tang Mango 19g',
      'Coffee 26g',
      'Milk 1L',
    ]);
    expect(draft.rawText, contains('3 pcs Coffee 26g 22.00 66.00'));
  });
  test('wrapped unlabeled numeric prices agree without a header', () {
    final draft = parse(['STORE', 'Coffee 26g', '3 22.00 66.00 V']);
    expect(draft.lines.single.quantity, 3);
    expect(draft.lines.single.grossAmountCents, 6600);
    expect(draft.lines.single.description, 'Coffee 26g');
  });
  test('unclear PC glyph retains count without choosing purchase unit', () {
    for (final marker in ['PO', 'PČ']) {
      final draft = parse(['STORE', 'Coffee 26g', '3 $marker 22.00 66.00 V']);
      expect(draft.lines.single.quantity, 3);
      expect(draft.lines.single.grossAmountCents, 6600);
      expect(draft.lines.single.description, 'Coffee 26g');
      expect(draft.lines.single.unit, isNull);
    }
  });
  test('joined OCR identity auto matches only the complete unique product', () {
    const product = Product(
      id: 'tang',
      name: 'Tang Mango',
      brand: 'Tang',
      variant: 'Mango',
      size: '19g',
    );
    expect(exactProductMatch('TangMango19g', [product]), product);
    expect(exactProductMatch('TangMango190g', [product]), isNull);
    expect(exactProductMatch('TangMango19gExtra', [product]), isNull);
    expect(exactProductMatch('Tang19g', [product]), isNull);
    const spice = Product(
      id: 'spice',
      name: 'Spice',
      brand: 'Brand',
      variant: 'Spice',
      size: '1.5oz',
    );
    expect(exactProductMatch('Brand Spice 1.5oz', [spice]), spice);
    expect(exactProductMatch('Brand Spice 1.5oz 2.5oz', [spice]), isNull);
    const eggs = Product(
      id: 'eggs',
      name: 'Eggs',
      brand: 'HappiNest',
      variant: 'Fresh Egg Extra Large',
      size: '12s',
    );
    expect(exactProductMatch('HappiNestFreshEggExtraLarge12s', [eggs]), eggs);
    expect(
      exactProductMatch('TangMango19g', [
        product,
        product.copyWith(id: 'duplicate'),
      ]),
      isNull,
    );
  });
  test(
    'Wellbest split rows resolve quantities and arithmetic, not pack units',
    () {
      final draft = parse([
        'WELLBEST',
        '001747347 BIRCH TREE FORTIFIED 64G TP',
        '10 X 15.75 157.50 V',
        '001500581 ARIEL LAU 58G',
        '1 X 93.00 93.00 V',
        'Total Items: 11',
        'TOTAL PHP 250.50',
      ]);
      expect(draft.lines, hasLength(2));
      expect(draft.lines.map((line) => line.quantity), [10, 1]);
      expect(draft.lines.map((line) => line.grossAmountCents), [15750, 9300]);
      expect(draft.lines.first.unit, isNull);
      expect(draft.detectedTotalCents, 25050);
    },
  );
  test('DALI quantities and prices agree; footer cannot become a purchase', () {
    final draft = parse([
      'DALI',
      'UFC Golden Fiesta Canola Oil 1L',
      '1 PC 144.00 144.00 V',
      'Mr. Zippy Kalamansi',
      '1 PC 27.50 27.50 V',
      'Wagyu Carne Norte 150g',
      '3 PC 21.00 63.00 V',
      'TOTAL 5 234.50',
      'MAYA PHP 234.50',
      'Warranty 5 pcs 1.00',
    ]);
    expect(draft.lines, hasLength(3));
    expect(draft.lines.map((line) => line.quantity), [1, 1, 3]);
    expect(draft.lines.map((line) => line.grossAmountCents), [
      14400,
      2750,
      6300,
    ]);
    expect(draft.lines.last.costPerPieceCents, 2100);
  });
  test(
    'cash heading and discount footer cannot override purchases or total',
    () {
      final draft = parse([
        'STORE',
        'CASH SALES',
        '2 pcs Coffee 44.00',
        'TOTAL: 2 Items 40.00',
        'Total Sales 35.71',
        'Total Discount 4.00',
      ]);
      expect(draft.lines, hasLength(1));
      expect(draft.detectedTotalCents, 4000);
      expect(draft.warnings.any((value) => value.contains('differ')), isTrue);
    },
  );
  test('unit-only row cannot borrow a size count from the product name', () {
    final draft = parse(['STORE', 'Skyflakes Sandwich 30', 'PC 69.50 V']);
    expect(draft.lines.single.quantity, isNull);
    expect(draft.lines.single.grossAmountCents, 6950);
  });
  test('labeled totals still require consistent printed arithmetic', () {
    final draft = parse([
      'STORE',
      'ITEM QTY PRICE AMOUNT',
      'Coffee 26G',
      '2 PC 22.00 44.09 V',
      'TOTAL 44.09',
    ]);
    expect(draft.lines.single.quantity, 2);
    expect(draft.lines.single.grossAmountCents, isNull);
  });
  test('multiplication symbol is a count marker, not pack conversion', () {
    final draft = parse(['STORE', 'Coffee 26G', '2 × 22.00 44.00 V']);
    expect(draft.lines.single.quantity, 2);
    expect(draft.lines.single.grossAmountCents, 4400);
    expect(draft.lines.single.unit, isNull);
  });
  test('incorrect arithmetic remains unresolved', () {
    final draft = parse(['STORE', 'Coffee 26G', '3 PC 21.00 62.00 V']);
    expect(draft.lines.single.quantity, 3);
    expect(draft.lines.single.grossAmountCents, isNull);
  });
  test(
    'Puregold numeric row before description binds only the next product',
    () {
      final draft = parse([
        'STORE',
        '2 x 11.80 23.60 V',
        '4809011392597 HOTDOG 12',
        '4 x 23.60 94.40 V',
        '4800093230632 BBQ 205G',
        'TOTAL 118.00',
      ]);
      expect(draft.lines.map((line) => line.quantity), [2, 4]);
      expect(draft.lines.map((line) => line.grossAmountCents), [2360, 9440]);
    },
  );
  test('Savemore @ prices, integer unit price and tax suffix', () {
    final draft = parse([
      'STORE',
      '2 OISHI 24G @7.95 15.90',
      '3 Tang Orange Mango 19g @21 63.00',
      'TOTAL DUE PHP 78.90',
    ]);
    expect(draft.lines.map((line) => line.grossAmountCents), [1590, 6300]);
    expect(draft.lines.map((line) => line.quantity), [2, 3]);
  });
  test('issued dates excluded and both purchase choices retain clock', () {
    final service = ReceiptPurchaseDateTime();
    final result = service.suggest(['08.10.26 16:00', 'Date Issued: 08/01/20']);
    expect(result.purchasedAt, isNull);
    expect(result.candidates.map((c) => c.date), [
      DateTime(2026, 8, 10, 16),
      DateTime(2026, 10, 8, 16),
    ]);
    expect(
      service.suggest([
        '08.10.26 16:00',
        'PTU Date Issue 06/04/2026',
      ], dateOrder: NumericDateOrder.dayFirst).purchasedAt,
      DateTime(2026, 10, 8, 16),
    );
  });
  test('catalog identity supports equivalent units without fuzzy merging', () {
    const oil = Product(
      id: 'oil',
      name: 'Oil',
      brand: 'UFC',
      variant: 'Golden Fiesta Canola Oil',
      size: '1L',
    );
    expect(
      exactProductMatch('UFC Golden Fiesta Canola Oil 1000ml', [oil]),
      oil,
    );
    expect(
      exactProductMatch('UFC Golden Fiesta Canola Oil 500ml', [oil]),
      isNull,
    );
    expect(
      exactProductMatch('UFC Golden Fiesta Canola Oil 1L 500ml', [oil]),
      isNull,
    );
    expect(exactProductMatch('UFC Canola 1L', [oil]), isNull);
    expect(
      exactProductMatch('UFC Golden Fiesta Canola Oil 1L', [
        oil,
        oil.copyWith(id: 'duplicate'),
      ]),
      isNull,
    );
  });
  for (final name in [
    'dali',
    'waltermart',
    'savemore',
    'puregold',
    'dali_enhanced',
    'waltermart_enhanced',
    'savemore_enhanced',
    'pos_demo',
  ]) {
    test('actual phone OCR replay: $name', () {
      final record =
          jsonDecode(
                File(
                  'test/fixtures/public_receipts/$name.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final lines = [
        for (final row in record['lines'] as List)
          OcrTextLine(
            text: row['text'] as String,
            left: (row['left'] as num).toDouble(),
            top: (row['top'] as num).toDouble(),
            width: (row['width'] as num).toDouble(),
            height: (row['height'] as num).toDouble(),
            tokens: [
              for (final token in row['tokens'] as List)
                OcrTextToken(
                  text: token['text'] as String,
                  left: (token['left'] as num).toDouble(),
                  top: (token['top'] as num).toDouble(),
                  width: (token['width'] as num).toDouble(),
                  height: (token['height'] as num).toDouble(),
                ),
            ],
          ),
      ];
      final draft = ReceiptParser().parse(
        imagePath: '/$name.jpg',
        textLines: lines,
      );
      // ignore: avoid_print
      print(
        '$name: ${jsonEncode([
          for (final line in draft.lines) {'description': line.description, 'quantity': line.quantity, 'amount': line.grossAmountCents},
        ])}; total ${draft.detectedTotalCents}',
      );
      expect(draft.lines.every((line) => !line.confirmed), isTrue);
      if (name == 'pos_demo') {
        expect(draft.lines, hasLength(3));
        expect(draft.lines.map((line) => line.quantity), [1, 1, 2]);
        expect(draft.lines.map((line) => line.grossAmountCents), [
          9975,
          3025,
          null,
        ]);
        expect(draft.detectedTotalCents, 16145);
      }
      if (name.startsWith('dali')) {
        final crackers = draft.lines.firstWhere(
          (line) => line.description.contains('Crackers 25g'),
        );
        expect(crackers.quantity, 10);
        expect(
          crackers.grossAmountCents,
          name.endsWith('_enhanced') ? isNull : 3750,
        );
        expect(draft.detectedTotalCents, 60275);
      } else if (name.startsWith('waltermart')) {
        final peanuts = draft.lines.firstWhere(
          (line) => line.description.contains('SUGO NUT'),
        );
        expect(peanuts.grossAmountCents, 3350);
        expect(peanuts.quantity, isNull);
        expect(draft.detectedTotalCents, 150262);
      } else if (name == 'puregold') {
        // This faded scan has no reliable monetary rows: never invent prices.
        expect(
          draft.lines.where((line) => line.grossAmountCents != null),
          isEmpty,
        );
      }
      if (name.startsWith('savemore')) {
        expect(draft.lines, hasLength(6));
        expect(draft.lines.first.quantity, 2);
        expect(draft.lines.first.grossAmountCents, 1590);
        expect(draft.detectedTotalCents, 19760);
        if (name.endsWith('_enhanced')) {
          expect(draft.lines.map((line) => line.grossAmountCents), [
            1590,
            3795,
            1025,
            6300,
            4100,
            2950,
          ]);
          expect(
            draft.lines.every((line) => !line.description.contains('@')),
            isTrue,
          );
        }
      }
    });
  }
}
