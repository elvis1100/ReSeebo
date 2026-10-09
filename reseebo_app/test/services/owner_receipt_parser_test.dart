import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/services/receipt_parser.dart';

void main() {
  final parser = ReceiptParser();

  List<OcrTextLine> loadLines(
    Map<String, dynamic> fixture, {
    double coordinateScale = 1,
  }) => (fixture['lines'] as List).map((entry) {
    final row = entry as Map<String, dynamic>;
    double number(String key) =>
        (row[key] as num? ?? 0).toDouble() * coordinateScale;
    return OcrTextLine(
      text: row['text'] as String,
      left: number('left'),
      top: number('top'),
      width: number('width'),
      height: number('height'),
      tokens: (row['tokens'] as List? ?? []).map((entry) {
        final token = entry as Map<String, dynamic>;
        double tokenNumber(String key) =>
            (token[key] as num? ?? 0).toDouble() * coordinateScale;
        return OcrTextToken(
          text: token['text'] as String,
          left: tokenNumber('left'),
          top: tokenNumber('top'),
          width: tokenNumber('width'),
          height: tokenNumber('height'),
        );
      }).toList(),
    );
  }).toList();

  ReceiptDraft parseRows(List<String> rows) => parser.parse(
    imagePath: '/receipt.jpg',
    textLines: rows.map((text) => OcrTextLine(text: text)).toList(),
  );

  final captureDirectory = Directory('test/fixtures/owner_receipts');
  final captures =
      captureDirectory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .map(
            (file) =>
                jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
          )
          .toList()
        ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));

  for (final fixture in captures.where(
    (fixture) => (fixture['id'] as String).startsWith('user_wellbest_'),
  )) {
    final captureId = fixture['id'] as String;
    test(
      '$captureId keeps the two independently verified purchases separate',
      () {
        final sourceLines = loadLines(fixture);
        final draft = parser.parse(
          imagePath: '/wellbest.jpg',
          textLines: sourceLines,
        );

        expect(draft.detectedTotalCents, 25050);
        expect(draft.lines, hasLength(2));
        expect(draft.rawText, contains('WELLBEST'));
        final birch = draft.lines[0];
        final ariel = draft.lines[1];
        expect(birch.description.toUpperCase(), contains('BIRCH TREE'));
        expect(ariel.description.toUpperCase(), contains('ARIEL'));
        expect(birch.description, isNot(ariel.description));
        final itemCodeAtStart = RegExp(r'^(?:D)?0?\d{7,}\b');
        expect(itemCodeAtStart.hasMatch(birch.description), isFalse);
        expect(itemCodeAtStart.hasMatch(ariel.description), isFalse);
        expect(birch.quantity, 10);
        expect(ariel.quantity, 1);
        expect(birch.printedItemCode, '001747347');
        final expectedArielCode = switch (captureId) {
          'user_wellbest_mlkit_original' => 'D01500381',
          'user_wellbest_mlkit_enhanced' => '001500381',
          _ => '001500581',
        };
        expect(ariel.printedItemCode, expectedArielCode);
        expect(birch.confirmed, isFalse);
        expect(ariel.confirmed, isFalse);

        if (captureId.contains('mlkit_')) {
          // The printed 13.75 x 10 contradicts Birch's 157.50 line amount.
          // Keep the captured evidence unresolved; do not repair OCR by arithmetic.
          expect(birch.grossAmountCents, isNull);
        } else {
          expect(birch.grossAmountCents, 15750);
        }
        expect(
          ariel.grossAmountCents,
          captureId == 'user_wellbest_ppocr_original' ? isNull : 9300,
        );

        // Description text may omit the printed code, but must not invent OCR
        // corrections or reinterpret Ariel's promotional 6+1 as its count.
        final raw = draft.rawText.toUpperCase();
        expect(raw, contains('ARIEL'));
        expect(ariel.quantity, isNot(7));
        expect(draft.textLines, orderedEquals(sourceLines));
        final snapshot = draft.snapshot();
        expect(snapshot.lines[0].printedItemCode, birch.printedItemCode);
        expect(snapshot.lines[1].printedItemCode, ariel.printedItemCode);
      },
    );
  }

  for (final fixture in captures.where(
    (fixture) => (fixture['id'] as String).startsWith('user_dali_'),
  )) {
    final captureId = fixture['id'] as String;
    test('$captureId retains three rows and leaves unread digits unresolved', () {
      final sourceLines = loadLines(fixture);
      final draft = parser.parse(
        imagePath: '/dali.jpg',
        textLines: sourceLines,
      );

      expect(draft.detectedTotalCents, 23450);
      expect(draft.lines, hasLength(3));
      final oil = draft.lines[0];
      final zippy = draft.lines[1];
      final wagi = draft.lines[2];

      // Canoia, Hagr, Hayr, I, and similar strings are deliberately retained
      // as recognized. Tests must not turn independent truth into OCR repairs.
      expect(oil.description.toUpperCase(), contains('UFC'));
      expect(oil.description.toUpperCase(), contains('CANOIA'));
      expect(oil.description.toUpperCase(), isNot(contains('CANOLA')));
      expect(zippy.description.toUpperCase(), contains('ZIPPY'));
      expect(wagi.description.toUpperCase(), contains('CARNE NORTE'));
      expect(wagi.description, contains(_thirdItemOcrIdentity(captureId)));

      expect(oil.quantity, isNull);
      expect(oil.unit, PurchaseUnit.piece);
      expect(oil.grossAmountCents, 14400);
      expect(zippy.grossAmountCents, 2750);
      expect(wagi.quantity, 3);
      expect(wagi.unit, PurchaseUnit.piece);
      expect(wagi.grossAmountCents, 6300);

      if (captureId.contains('mlkit_')) {
        expect(zippy.quantity, 1);
        expect(zippy.unit, PurchaseUnit.piece);
      } else {
        // PP-OCR's source rows say `I PC` or `| PC`; they do not prove a digit.
        expect(zippy.quantity, isNull);
      }
      expect(draft.textLines, orderedEquals(sourceLines));
    });
  }

  test('owner capture suggestions are stable across OCR coordinate scales', () {
    for (final fixture in captures) {
      final baseline = parser.parse(
        imagePath: '/scaled-owner.jpg',
        textLines: loadLines(fixture),
      );
      final baselineItems = baseline.lines
          .map(
            (line) => (
              line.description,
              line.printedItemCode,
              line.quantity,
              line.unit,
              line.grossAmountCents,
            ),
          )
          .toList();
      for (final scale in [.5, 2.5]) {
        final scaled = parser.parse(
          imagePath: '/scaled-owner.jpg',
          textLines: loadLines(fixture, coordinateScale: scale),
        );
        expect(
          scaled.detectedTotalCents,
          baseline.detectedTotalCents,
          reason: '${fixture['id']} at scale $scale',
        );
        expect(
          scaled.lines
              .map(
                (line) => (
                  line.description,
                  line.printedItemCode,
                  line.quantity,
                  line.unit,
                  line.grossAmountCents,
                ),
              )
              .toList(),
          orderedEquals(baselineItems),
          reason: '${fixture['id']} at scale $scale',
        );
      }
    }
  });

  test('a count row cannot cross the next product description', () {
    final draft = parseRows([
      'Supplier A',
      '10 X 13.75',
      '157.50',
      'ARIEL LIQUID 58G',
      '1 X 93.00',
    ]);

    final ariel = draft.lines.where(
      (line) => line.description.toUpperCase().contains('ARIEL'),
    );
    expect(ariel, hasLength(1));
    expect(ariel.single.quantity, isNot(10));
  });

  test('a footer amount stays out of the preceding product row', () {
    final draft = parseRows([
      'Supplier A',
      'Coffee 84.00',
      'TOTAL',
      '500.00',
      'CASH 1000.00',
      'CHANGE 500.00',
    ]);

    expect(draft.lines, hasLength(1));
    expect(draft.lines.single.description, 'Coffee');
    expect(draft.lines.single.grossAmountCents, 8400);
    expect(draft.detectedTotalCents, 50000);
  });

  test('an uncertain terminal glyph does not become a valid price marker', () {
    final draft = parseRows(['Supplier A', 'Coffee 84.00 Ų']);

    expect(draft.lines, hasLength(1));
    expect(draft.lines.single.description, 'Coffee');
    expect(draft.lines.single.grossAmountCents, 8400);
    expect(
      draft.lines.single.warnings.any(
        (warning) => warning.toLowerCase().contains('marker'),
      ),
      isTrue,
    );
  });

  test('arbitrary suffix text is not accepted as a money marker', () {
    final draft = parseRows(['Supplier A', 'Coffee 84.00 VAT']);

    expect(draft.lines.where((line) => line.grossAmountCents == 8400), isEmpty);
  });

  test('malformed money is not extracted as a line amount', () {
    final draft = parseRows(['Supplier A', 'Coffee 1,2.00']);

    expect(draft.lines.where((line) => line.grossAmountCents != null), isEmpty);
  });

  test('numeric brand identity is not treated as a purchase count', () {
    final draft = parseRows(['Supplier A', '7 UP 42.00']);

    expect(draft.lines, hasLength(1));
    expect(draft.lines.single.description, '7 UP');
    expect(draft.lines.single.quantity, isNull);
  });

  test('a bounded footer between name and count blocks item ownership', () {
    final draft = parser.parse(
      imagePath: '/bounded-footer.jpg',
      textLines: [
        const OcrTextLine(text: 'Supplier A', top: -50, width: 100, height: 10),
        const OcrTextLine(
          text: 'Coffee 26G',
          left: 40,
          top: 10,
          width: 100,
          height: 10,
        ),
        const OcrTextLine(
          text: 'CASH PAYMENT',
          left: 40,
          top: 23,
          width: 100,
          height: 10,
        ),
        const OcrTextLine(
          text: '3 PC',
          left: 40,
          top: 36,
          width: 40,
          height: 10,
        ),
        const OcrTextLine(
          text: '21.00',
          left: 140,
          top: 36,
          width: 35,
          height: 10,
        ),
        const OcrTextLine(
          text: '63.00',
          left: 240,
          top: 36,
          width: 35,
          height: 10,
        ),
      ],
    );

    expect(draft.lines, hasLength(1));
    expect(draft.lines.single.description, 'Coffee 26G');
    expect(draft.lines.single.quantity, isNull);
    expect(draft.lines.single.grossAmountCents, isNull);
  });

  test('bounded item rows separate a numeric brand and a promotion', () {
    final draft = parser.parse(
      imagePath: '/bounded-items.jpg',
      textLines: [
        const OcrTextLine(
          text: '7 UP 2L',
          left: 40,
          top: 10,
          width: 90,
          height: 10,
        ),
        const OcrTextLine(
          text: '2 PC 10.00',
          left: 40,
          top: 22,
          width: 90,
          height: 10,
        ),
        const OcrTextLine(
          text: '20.00',
          left: 240,
          top: 22,
          width: 40,
          height: 10,
        ),
        const OcrTextLine(
          text: '6+1 ARIEL LAU 58G',
          left: 40,
          top: 45,
          width: 150,
          height: 10,
        ),
        const OcrTextLine(
          text: '1 PC 93.00',
          left: 40,
          top: 57,
          width: 90,
          height: 10,
        ),
        const OcrTextLine(
          text: '93.00',
          left: 240,
          top: 57,
          width: 40,
          height: 10,
        ),
      ],
    );

    expect(draft.lines, hasLength(2));
    expect(draft.lines[0].description, '7 UP 2L');
    expect(draft.lines[0].quantity, 2);
    expect(draft.lines[0].grossAmountCents, 2000);
    expect(draft.lines[1].description, '6+1 ARIEL LAU 58G');
    expect(draft.lines[1].quantity, 1);
    expect(draft.lines[1].grossAmountCents, 9300);
  });

  test(
    'a wrapped numeric row with an uncertain Unicode marker keeps both prices',
    () {
      final draft = parser.parse(
        imagePath: '/bounded-unicode-marker.jpg',
        textLines: [
          const OcrTextLine(
            text: 'Coffee 26G',
            left: 40,
            top: 10,
            width: 100,
            height: 10,
          ),
          const OcrTextLine(
            text: '3 PC 21.00 63.00 Ų',
            left: 40,
            top: 22,
            width: 230,
            height: 10,
            tokens: [
              OcrTextToken(text: '3', left: 40, top: 22, width: 6, height: 10),
              OcrTextToken(
                text: 'PC',
                left: 50,
                top: 22,
                width: 14,
                height: 10,
              ),
              OcrTextToken(
                text: '21.00',
                left: 120,
                top: 22,
                width: 32,
                height: 10,
              ),
              OcrTextToken(
                text: '63.00',
                left: 220,
                top: 22,
                width: 32,
                height: 10,
              ),
              OcrTextToken(
                text: 'Ų',
                left: 258,
                top: 22,
                width: 12,
                height: 10,
              ),
            ],
          ),
        ],
      );

      expect(draft.lines, hasLength(1));
      expect(draft.lines.single.description, 'Coffee 26G');
      expect(draft.lines.single.quantity, 3);
      expect(draft.lines.single.unit, PurchaseUnit.piece);
      expect(draft.lines.single.grossAmountCents, 6300);
      expect(
        draft.lines.single.warnings.any(
          (warning) => warning.toLowerCase().contains('marker'),
        ),
        isTrue,
      );
    },
  );
}

String _thirdItemOcrIdentity(String captureId) {
  if (captureId.contains('mlkit_enhanced')) return 'Hayr';
  if (captureId.contains('mlkit_original')) return 'Hagr';
  return 'Wagi';
}
