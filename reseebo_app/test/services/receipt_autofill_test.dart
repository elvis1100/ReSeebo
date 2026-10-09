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
  test('Wellbest split rows resolve quantities and arithmetic, not pack units', () {
    final draft = parse([
      'WELLBEST', '001747347 BIRCH TREE FORTIFIED 64G TP',
      '10 X 15.75 157.50 V', '001500581 ARIEL LAU 58G',
      '1 X 93.00 93.00 V', 'Total Items: 11', 'TOTAL PHP 250.50',
    ]);
    expect(draft.lines, hasLength(2));
    expect(draft.lines.map((line) => line.quantity), [10, 1]);
    expect(draft.lines.map((line) => line.grossAmountCents), [15750, 9300]);
    expect(draft.lines.first.unit, isNull);
    expect(draft.detectedTotalCents, 25050);
  });
  test('DALI quantities and prices agree; footer cannot become a purchase', () {
    final draft = parse(['DALI', 'UFC Golden Fiesta Canola Oil 1L',
      '1 PC 144.00 144.00 V', 'Mr. Zippy Kalamansi',
      '1 PC 27.50 27.50 V', 'Wagyu Carne Norte 150g',
      '3 PC 21.00 63.00 V', 'TOTAL 5 234.50',
      'MAYA PHP 234.50', 'Warranty 5 pcs 1.00']);
    expect(draft.lines, hasLength(3));
    expect(draft.lines.map((line) => line.quantity), [1, 1, 3]);
    expect(draft.lines.map((line) => line.grossAmountCents), [14400, 2750, 6300]);
    expect(draft.lines.last.costPerPieceCents, 2100);
  });
  test('incorrect arithmetic remains unresolved', () {
    final draft = parse(['STORE', 'Coffee 26G', '3 PC 21.00 62.00 V']);
    expect(draft.lines.single.quantity, 3);
    expect(draft.lines.single.grossAmountCents, isNull);
  });
  test('Puregold numeric row before description binds only the next product', () {
    final draft = parse(['STORE', '2 x 11.80 23.60 V',
      '4809011392597 HOTDOG 12', '4 x 23.60 94.40 V', '4800093230632 BBQ 205G',
      'TOTAL 118.00']);
    expect(draft.lines.map((line) => line.quantity), [2, 4]);
    expect(draft.lines.map((line) => line.grossAmountCents), [2360, 9440]);
  });
  test('Savemore @ prices, integer unit price and tax suffix', () {
    final draft = parse(['STORE', '2 OISHI 24G @7.95 15.90',
      '3 Tang Orange Mango 19g @21 63.00', 'TOTAL DUE PHP 78.90']);
    expect(draft.lines.map((line) => line.grossAmountCents), [1590, 6300]);
    expect(draft.lines.map((line) => line.quantity), [2, 3]);
  });
  test('issued dates excluded and both purchase choices retain clock', () {
    final service = ReceiptPurchaseDateTime();
    final result = service.suggest(['08.10.26 16:00', 'Date Issued: 08/01/20']);
    expect(result.purchasedAt, isNull);
    expect(result.candidates.map((c) => c.date), [DateTime(2026, 8, 10, 16), DateTime(2026, 10, 8, 16)]);
    expect(service.suggest(['08.10.26 16:00', 'PTU Date Issue 06/04/2026'],
      dateOrder: NumericDateOrder.dayFirst).purchasedAt, DateTime(2026, 10, 8, 16));
  });
  test('catalog identity supports equivalent units without fuzzy merging', () {
    const oil = Product(id: 'oil', name: 'Oil', brand: 'UFC',
      variant: 'Golden Fiesta Canola Oil', size: '1L');
    expect(exactProductMatch('UFC Golden Fiesta Canola Oil 1000ml', [oil]), oil);
    expect(exactProductMatch('UFC Golden Fiesta Canola Oil 500ml', [oil]), isNull);
    expect(exactProductMatch('UFC Golden Fiesta Canola Oil 1L 500ml', [oil]), isNull);
    expect(exactProductMatch('UFC Canola 1L', [oil]), isNull);
    expect(exactProductMatch('UFC Golden Fiesta Canola Oil 1L', [oil, oil.copyWith(id: 'duplicate')]), isNull);
  });
  for (final name in ['dali', 'waltermart', 'savemore', 'puregold']) {
    test('actual phone OCR replay: $name', () {
      final record = jsonDecode(File('test/fixtures/public_receipts/$name.json').readAsStringSync()) as Map<String, dynamic>;
      final lines = [for (final row in record['lines'] as List) OcrTextLine(
        text: row['text'] as String, left: (row['left'] as num).toDouble(),
        top: (row['top'] as num).toDouble(), width: (row['width'] as num).toDouble(),
        height: (row['height'] as num).toDouble(),
        tokens: [for (final token in row['tokens'] as List) OcrTextToken(
          text: token['text'] as String, left: (token['left'] as num).toDouble(),
          top: (token['top'] as num).toDouble(), width: (token['width'] as num).toDouble(),
          height: (token['height'] as num).toDouble())],
      )];
      final draft = ReceiptParser().parse(imagePath: '/$name.jpg', textLines: lines);
      // ignore: avoid_print
      print('$name: ${jsonEncode([for (final line in draft.lines) {
        'description': line.description, 'quantity': line.quantity, 'amount': line.grossAmountCents,
      }])}; total ${draft.detectedTotalCents}');
      expect(draft.lines.every((line) => !line.confirmed), isTrue);
      if (name == 'savemore') {
        expect(draft.lines, hasLength(6));
        expect(draft.lines.first.quantity, 2);
        expect(draft.lines.first.grossAmountCents, 1590);
        expect(draft.detectedTotalCents, 19760);
      }
    });
  }
}
