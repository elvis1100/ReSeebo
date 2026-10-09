import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/services/receipt_ocr_comparison.dart';
import 'package:reseebo_app/core/services/receipt_parser.dart';

ReceiptDraft compare(List<String> primary, List<String> original) {
  final page = ReceiptOcrPage(
    imagePath: '/original.jpg',
    recognitionImagePath: '/enhanced.jpg',
    textLines: primary.map((text) => OcrTextLine(text: text)).toList(),
    originalTextLines: original.map((text) => OcrTextLine(text: text)).toList(),
  );
  final draft = ReceiptParser().parsePages(pages: [page]);
  const ReceiptOcrComparison().supplement(draft, [page]);
  return draft;
}

List<OcrTextLine> fixture(String name) {
  final json =
      jsonDecode(
            File('test/fixtures/public_receipts/$name.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  return (json['lines'] as List).map((entry) {
    final row = entry as Map<String, dynamic>;
    return OcrTextLine(
      text: row['text'] as String,
      left: (row['left'] as num).toDouble(),
      top: (row['top'] as num).toDouble(),
      width: (row['width'] as num).toDouble(),
      height: (row['height'] as num).toDouble(),
      tokens: [
        for (final token in (row['tokens'] as List? ?? []))
          OcrTextToken(
            text: token['text'] as String,
            left: (token['left'] as num).toDouble(),
            top: (token['top'] as num).toDouble(),
            width: (token['width'] as num).toDouble(),
            height: (token['height'] as num).toDouble(),
          ),
      ],
    );
  }).toList();
}

void main() {
  test(
    'fills missing fields on a unique identical product without adding rows',
    () {
      final draft = compare(
        ['STORE', 'Coffee 26g', 'TOTAL 44.00'],
        [
          'STORE',
          '2 pcs Coffee 26g 44.00',
          '1 pcs Other 1L 50.00',
          'TOTAL 94.00',
        ],
      );
      expect(draft.lines, hasLength(1));
      expect(draft.lines.single.quantity, 2);
      expect(draft.lines.single.grossAmountCents, 4400);
      expect(draft.lines.single.unit, isNull);
      expect(draft.detectedTotalCents, 4400);
      expect(draft.lines.single.confirmed, isFalse);
    },
  );

  test('disagreeing count prevents borrowing missing amount', () {
    final draft = compare(
      ['STORE', '2 pcs Coffee 26g'],
      ['STORE', '3 pcs Coffee 26g 66.00'],
    );
    expect(draft.lines.single.quantity, 2);
    expect(draft.lines.single.grossAmountCents, isNull);
    expect(draft.lines.single.warnings.join(' '), contains('disagree'));
  });

  test('conflicting printed arithmetic cannot be rescued by another pass', () {
    final draft = compare(
      ['STORE', '2 pcs Coffee 26g 22.00 45.00'],
      ['STORE', '2 pcs Coffee 26g 22.00 44.00'],
    );
    expect(draft.lines.single.grossAmountCents, isNull);
  });

  test('repeated descriptions and different sizes cannot borrow evidence', () {
    final draft = compare(
      ['STORE', 'Coffee 1.5L', 'Coffee 26g', 'Coffee 26g'],
      ['STORE', '2 pcs Coffee 15L 44.00', '2 pcs Coffee 26g 44.00'],
    );
    expect(draft.lines, hasLength(3));
    expect(draft.lines.every((line) => line.grossAmountCents == null), isTrue);
  });

  test('owner-edited blank fields and confirmed lines are preserved', () {
    final page = ReceiptOcrPage(
      imagePath: '/source',
      textLines: const [
        OcrTextLine(text: 'STORE'),
        OcrTextLine(text: 'Coffee 26g'),
      ],
      originalTextLines: const [
        OcrTextLine(text: 'STORE'),
        OcrTextLine(text: '2 pcs Coffee 26g 44.00'),
      ],
    );
    final draft = ReceiptParser().parsePages(pages: [page]);
    draft.lines.single
      ..quantityEdited = true
      ..amountEdited = true;
    const ReceiptOcrComparison().supplement(draft, [page]);
    expect(draft.lines.single.quantity, isNull);
    expect(draft.lines.single.grossAmountCents, isNull);
    draft.lines.single
      ..quantityEdited = false
      ..amountEdited = false
      ..confirmed = true;
    const ReceiptOcrComparison().supplement(draft, [page]);
    expect(draft.lines.single.quantity, isNull);
    expect(page.snapshot().originalTextLines.last.text, contains('44.00'));
  });

  test('actual public OCR retains selected rows while comparing originals', () {
    for (final name in ['dali', 'waltermart', 'savemore']) {
      final page = ReceiptOcrPage(
        imagePath: '/$name.jpg',
        textLines: fixture('${name}_enhanced'),
        originalTextLines: fixture(name),
      );
      final draft = ReceiptParser().parsePages(pages: [page]);
      final descriptions = draft.lines.map((line) => line.description).toList();
      final quantitiesBefore = draft.lines
          .where((line) => line.quantity != null)
          .length;
      final amountsBefore = draft.lines
          .where((line) => line.grossAmountCents != null)
          .length;
      const ReceiptOcrComparison().supplement(draft, [page]);
      expect(draft.lines.map((line) => line.description), descriptions);
      final quantitiesAfter = draft.lines
          .where((line) => line.quantity != null)
          .length;
      final amountsAfter = draft.lines
          .where((line) => line.grossAmountCents != null)
          .length;
      expect(quantitiesAfter, greaterThanOrEqualTo(quantitiesBefore));
      expect(amountsAfter, greaterThanOrEqualTo(amountsBefore));
      // Completeness counts are not accuracy measurements against source pixels.
      // ignore: avoid_print
      print(
        '$name: quantities $quantitiesBefore->$quantitiesAfter, amounts $amountsBefore->$amountsAfter',
      );
    }
  });
}
