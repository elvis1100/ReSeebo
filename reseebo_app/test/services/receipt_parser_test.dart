import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/services/receipt_parser.dart';

void main() {
  final parser = ReceiptParser();

  final fixtures =
      Directory('test/fixtures/receipts')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in fixtures) {
    final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    test('synthetic fixture: ${fixture['name']}', () {
      final lines = (fixture['lines'] as List).map((entry) {
        final row = entry as Map<String, dynamic>;
        double bound(String key) => (row[key] as num? ?? 0).toDouble();
        return OcrTextLine(
          text: row['text'] as String,
          left: bound('left'),
          top: bound('top'),
          width: bound('width'),
          height: bound('height'),
          tokens: (row['tokens'] as List? ?? []).map((entry) {
            final token = entry as Map<String, dynamic>;
            double value(String key) => (token[key] as num? ?? 0).toDouble();
            return OcrTextToken(
              text: token['text'] as String,
              left: value('left'),
              top: value('top'),
              width: value('width'),
              height: value('height'),
            );
          }).toList(),
        );
      }).toList();
      final draft = parser.parse(imagePath: '/original.jpg', textLines: lines);
      final expected = fixture['expected'] as Map<String, dynamic>;
      expect(
        draft.purchasedAt,
        expected['date'] == null
            ? null
            : DateTime.parse(expected['date'] as String),
      );
      expect(draft.dateConfirmed, isFalse);
      expect(draft.textLines, orderedEquals(lines));
      for (final source in lines) {
        expect(draft.rawText, contains(source.text));
      }
      if (expected['warning'] != null) {
        expect(
          draft.warnings.any(
            (warning) => warning.contains(expected['warning'] as String),
          ),
          isTrue,
        );
      }
      final items = expected['lines'] as List;
      expect(draft.lines, hasLength(items.length));
      for (var index = 0; index < items.length; index++) {
        final item = items[index] as Map<String, dynamic>;
        final actual = draft.lines[index];
        expect(actual.description, item['description']);
        expect(actual.quantity, item['quantity']);
        expect(actual.unit?.name, item['unit']);
        expect(actual.grossAmountCents, item['amount']);
        expect(actual.confirmed, isFalse);
        if (item['warning'] != null) {
          expect(
            actual.warnings.any(
              (warning) => warning.contains(item['warning'] as String),
            ),
            isTrue,
          );
        }
      }
    });
  }

  test('retains original and recognition evidence for every ordered photo', () {
    final pages = [
      const ReceiptOcrPage(
        imagePath: '/a.jpg',
        recognitionImagePath: '/a-crop.jpg',
        textLines: [
          OcrTextLine(text: 'Supplier A'),
          OcrTextLine(text: '1 pcs Coffee 84.00'),
        ],
      ),
      const ReceiptOcrPage(
        imagePath: '/b.jpg',
        recognitionImagePath: '/b-rotate.jpg',
        textLines: [
          OcrTextLine(text: 'Supplier A'),
          OcrTextLine(text: '1 pcs Milk 40.00'),
        ],
      ),
    ];
    final draft = parser.parsePages(pages: pages);
    expect(draft.ocrPages.map((page) => page.imagePath), ['/a.jpg', '/b.jpg']);
    expect(draft.ocrPages.map((page) => page.recognitionImagePath), [
      '/a-crop.jpg',
      '/b-rotate.jpg',
    ]);
    expect(
      draft.ocrPages[1].textLines
          .singleWhere((line) => line.text.contains('Milk'))
          .text,
      '1 pcs Milk 40.00',
    );
    final single = parser.parse(
      imagePath: '/a.jpg',
      recognitionImagePath: '/a-crop.jpg',
      textLines: pages.first.textLines,
    );
    expect(single.ocrPages.single.recognitionImagePath, '/a-crop.jpg');
  });

  test('aligns separately recognized item columns by text bounds', () {
    final lines = [
      const OcrTextLine(
        text: '168.00',
        left: 200,
        top: 52,
        width: 50,
        height: 10,
      ),
      const OcrTextLine(text: 'Supplier A', top: 0, width: 90, height: 12),
      const OcrTextLine(
        text: '2026-10-08 14:30',
        top: 20,
        width: 100,
        height: 12,
      ),
      const OcrTextLine(
        text: 'BRAND X COF ORIG 26G',
        left: 30,
        top: 50,
        width: 150,
        height: 14,
      ),
      const OcrTextLine(text: '2', left: 0, top: 51, width: 10, height: 12),
      const OcrTextLine(text: 'TOTAL 168.00', top: 80, width: 100, height: 12),
    ];
    final draft = parser.parse(
      imagePath: '/original.jpg',
      recognitionImagePath: '/rotated.jpg',
      textLines: lines,
    );
    expect(draft.supplierName, 'Supplier A');
    expect(draft.purchasedAt, DateTime(2026, 10, 8, 14, 30));
    expect(draft.hasPurchaseTime, isTrue);
    expect(draft.dateConfirmed, isFalse);
    expect(draft.lines.single.description, 'BRAND X COF ORIG 26G');
    expect(draft.lines.single.quantity, 2);
    expect(draft.lines.single.unit, isNull);
    expect(draft.lines.single.grossAmountCents, 16800);
    expect(draft.lines.single.confirmed, isFalse);
    expect(draft.detectedTotalCents, 16800);
    expect(draft.textLines.length, lines.length);
    expect(draft.imagePath, '/original.jpg');
    expect(draft.recognitionImagePath, '/rotated.jpg');
  });

  test('ambiguous numeric dates remain unresolved rather than guessed', () {
    final draft = parser.parse(
      imagePath: '/image.jpg',
      textLines: [
        const OcrTextLine(text: 'Supplier B'),
        const OcrTextLine(text: '08/10/2026'),
        const OcrTextLine(text: 'Brand X 1 pack 78.00'),
      ],
    );
    expect(draft.purchasedAt, isNull);
    expect(
      draft.warnings.any((warning) => warning.contains('ambiguous')),
      isTrue,
    );
    expect(draft.lines.single.unit, PurchaseUnit.pack);
    expect(draft.lines.single.piecesPerPack, isNull);
  });

  test(
    'discounts flag review without deducting an already net amount twice',
    () {
      final draft = parser.parse(
        imagePath: '/image.jpg',
        textLines: [
          const OcrTextLine(text: 'Supplier C'),
          const OcrTextLine(text: '8 OCT 2026'),
          const OcrTextLine(text: 'Coffee 2 packs 10 pcs/pack 160.00'),
          const OcrTextLine(text: 'Discount 8.00'),
          const OcrTextLine(text: 'VAT 19.20'),
          const OcrTextLine(text: 'TOTAL 160.00'),
          const OcrTextLine(text: 'CASH 200.00'),
          const OcrTextLine(text: 'CHANGE 40.00'),
        ],
      );
      expect(draft.lines.length, 1);
      expect(draft.lines.single.quantity, 2);
      expect(draft.lines.single.piecesPerPack, 10);
      expect(draft.lines.single.discountCents, 0);
      expect(draft.lines.single.netAmountCents, 16000);
      expect(
        draft.lines.single.warnings.any(
          (warning) => warning.contains('final amount paid'),
        ),
        isTrue,
      );
      expect(draft.detectedTotalCents, 16000);
    },
  );
  ReceiptDraft parseRows(List<String> rows) => parser.parse(
    imagePath: '/original.jpg',
    textLines: rows.map((text) => OcrTextLine(text: text)).toList(),
  );

  for (final printed in [
    'October 9, 2026 2:30 PM',
    'OCT 09 26 14:30',
    '09-OCT-26 02:30 p.m.',
    '9 October 2026 14:30:00',
  ]) {
    test('suggests an English purchase date and time: $printed', () {
      final draft = parseRows(['Supplier A', printed, '1 pcs Coffee 84.00']);
      expect(draft.purchasedAt, DateTime(2026, 10, 9, 14, 30));
      expect(draft.hasPurchaseTime, isTrue);
      expect(draft.dateConfirmed, isFalse);
      expect(draft.lines.single.quantity, 1);
      expect(draft.lines.single.unit, PurchaseUnit.piece);
      expect(draft.rawText, contains(printed));
    });
  }

  for (final clockFirst in [false, true]) {
    test(
      'uses an adjacent standalone clock ${clockFirst ? 'before' : 'after'} the date',
      () {
        final dateAndTime = ['October 9, 2026', '02:30 PM'];
        final draft = parseRows([
          'Supplier A',
          ...(clockFirst ? dateAndTime.reversed : dateAndTime),
          '1 pcs Coffee 84.00',
        ]);
        expect(draft.purchasedAt, DateTime(2026, 10, 9, 14, 30));
        expect(draft.hasPurchaseTime, isTrue);
        expect(draft.dateConfirmed, isFalse);
      },
    );
  }

  test(
    'a labeled clock before a separated date preserves midnight correctly',
    () {
      final draft = parseRows([
        'Supplier A',
        'Time: 12:05 AM',
        'Receipt No 123',
        'Date: 09-OCT-26',
      ]);
      expect(draft.purchasedAt, DateTime(2026, 10, 9, 0, 5));
      expect(draft.hasPurchaseTime, isTrue);
    },
  );

  test(
    'equal numeric day and month is unambiguous; distinct ones need review',
    () {
      expect(
        parseRows(['Supplier A', '09/09/26']).purchasedAt,
        DateTime(2026, 9, 9),
      );
      expect(parseRows(['Supplier A', '09/10/26']).purchasedAt, isNull);
    },
  );

  test(
    'unrelated expiry manufacture and card dates cannot override purchase evidence',
    () {
      final draft = parseRows([
        'Supplier A',
        'Expiry date: 2027-02-20 14:30',
        'Manufacture date: October 8, 2026',
        'CARD VALID THRU 12/12/2028',
        'Date: October 9, 2026',
        'Time: 14:35',
        'Opening time: 08:00',
        '1 pcs Coffee 84.00',
      ]);
      expect(draft.purchasedAt, DateTime(2026, 10, 9, 14, 35));
      expect(draft.hasPurchaseTime, isTrue);
      expect(draft.lines, hasLength(1));
      expect(
        draft.warnings.any((warning) => warning.contains('differ')),
        isFalse,
      );
      final expiryOnly = parseRows(['Supplier A', 'EXP 2027-02-20']);
      expect(expiryOnly.purchasedAt, isNull);
    },
  );

  for (final printed in ['February 30, 2026', '2026-13-09', '31/02/26']) {
    test('rejects invalid calendar date $printed without rollover', () {
      final draft = parseRows(['Supplier A', printed]);
      expect(draft.purchasedAt, isNull);
      expect(
        draft.warnings.any((warning) => warning.contains('invalid')),
        isTrue,
      );
    });
  }

  for (final clock in ['25:30', '14:60', '14:30:60', '00:30 AM', '14:30 PM']) {
    test('rejects invalid purchase clock $clock without rollover', () {
      final draft = parseRows([
        'Supplier A',
        'Date: October 9, 2026',
        'Time: $clock',
      ]);
      expect(draft.purchasedAt, DateTime(2026, 10, 9));
      expect(draft.hasPurchaseTime, isFalse);
      expect(
        draft.warnings.any((warning) => warning.contains('invalid')),
        isTrue,
      );
    });
  }

  test('date and time conflicts stay unresolved for review', () {
    final dates = parseRows([
      'Supplier A',
      '2026-10-09 14:30',
      'Date: 2026-10-08',
    ]);
    expect(dates.purchasedAt, isNull);
    expect(dates.hasPurchaseTime, isFalse);
    expect(
      dates.warnings.any((warning) => warning.contains('dates differ')),
      isTrue,
    );
    final times = parseRows(['Supplier A', '2026-10-09 14:30', 'Time: 14:31']);
    expect(times.purchasedAt, DateTime(2026, 10, 9));
    expect(times.hasPurchaseTime, isFalse);
    expect(
      times.warnings.any((warning) => warning.contains('times differ')),
      isTrue,
    );
  });

  test('an unrelated distant unlabeled clock stays unknown', () {
    final draft = parseRows([
      'Supplier A',
      '2026-10-09',
      '1 pcs Coffee 84.00',
      'TOTAL 84.00',
      '15:30',
    ]);
    expect(draft.purchasedAt, DateTime(2026, 10, 9));
    expect(draft.hasPurchaseTime, isFalse);
  });

  test('an English date in the first row cannot become the supplier name', () {
    final draft = parseRows([
      'October 9, 2026',
      'Supplier A',
      '1 pcs Coffee 84.00',
    ]);
    expect(draft.supplierName, 'Supplier A');
  });

  test(
    'later page time enriches the same date and conflicting page clocks remain unknown',
    () {
      ReceiptOcrPage page(String path, String metadata) => ReceiptOcrPage(
        imagePath: path,
        textLines: [
          const OcrTextLine(text: 'Supplier A'),
          OcrTextLine(text: metadata),
        ],
      );
      final enriched = parser.parsePages(
        pages: [
          page('/a.jpg', 'Date: October 9, 2026'),
          page('/b.jpg', '2026-10-09 14:30'),
        ],
      );
      expect(enriched.purchasedAt, DateTime(2026, 10, 9, 14, 30));
      expect(enriched.hasPurchaseTime, isTrue);
      expect(enriched.dateConfirmed, isFalse);
      final conflict = parser.parsePages(
        pages: [
          page('/a.jpg', '2026-10-09 14:30'),
          page('/b.jpg', '2026-10-09 14:31'),
        ],
      );
      expect(conflict.purchasedAt, DateTime(2026, 10, 9));
      expect(conflict.hasPurchaseTime, isFalse);
      expect(
        conflict.warnings.any((warning) => warning.contains('times differ')),
        isTrue,
      );
    },
  );

  for (final count in ['2.00', '2.50']) {
    test(
      'a labeled amount table retains the product after $count pack count',
      () {
        final draft = parseRows([
          'SUPPLIER A',
          'QTY DESCRIPTION UNIT PRICE AMOUNT',
          '$count packs Coffee Original 26G 84.00 168.00',
        ]);
        expect(draft.lines, hasLength(1));
        expect(
          draft.lines.single.description,
          '$count packs Coffee Original 26G',
        );
        expect(draft.lines.single.quantity, count == '2.00' ? 2 : null);
        expect(
          draft.lines.single.unit,
          count == '2.00' ? PurchaseUnit.pack : null,
        );
        expect(
          draft.lines.single.grossAmountCents,
          count == '2.00' ? 16800 : null,
        );
        expect(draft.lines.single.confirmed, isFalse);
        expect(
          draft.rawText,
          contains('$count packs Coffee Original 26G 84.00 168.00'),
        );
      },
    );
  }

  test(
    'maps wrapped description and whole decimal quantities without losing raw OCR',
    () {
      final draft = parseRows([
        'SUPPLIER A',
        '2026-10-09',
        'COFFEE ORIGINAL 26G',
        '2.00 168.00',
        'TOTAL 168.00',
      ]);
      expect(draft.lines.single.description, 'COFFEE ORIGINAL 26G');
      expect(draft.lines.single.quantity, 2);
      expect(draft.lines.single.unit, isNull);
      expect(draft.lines.single.grossAmountCents, 16800);
      expect(draft.rawText, contains('COFFEE ORIGINAL 26G\n2.00 168.00'));
    },
  );

  test('labeled table maps trailing quantity, unit price and line total', () {
    final draft = parseRows([
      'OFFICIAL RECEIPT',
      'SUPPLIER A',
      'Receipt No. 00123',
      'DESCRIPTION QTY UNIT PRICE AMOUNT',
      'COFFEE 26G 2 84.00 168.00',
      'TOTAL 168.00',
      'CASH 200.00',
    ]);
    expect(draft.supplierName, 'SUPPLIER A');
    expect(draft.receiptNumber, '00123');
    expect(draft.lines.single.quantity, 2);
    expect(draft.lines.single.description, 'COFFEE 26G');
    expect(draft.lines.single.grossAmountCents, 16800);
    expect(draft.lines.single.unit, isNull);
  });

  test(
    'bounded labeled columns populate quantity and amount without treating unit price as total',
    () {
      OcrTextLine cell(String text, double x, double y) =>
          OcrTextLine(text: text, left: x, top: y, width: 40, height: 12);
      final draft = parser.parse(
        imagePath: '/original.jpg',
        textLines: [
          cell('Supplier A', 0, 0),
          cell('DESCRIPTION', 0, 30),
          cell('QTY PCS', 150, 30),
          cell('UNIT PRICE', 220, 30),
          cell('AMOUNT', 300, 30),
          cell('COFFEE 26G', 0, 50),
          cell('2.00', 150, 50),
          cell('84.00', 220, 50),
          cell('168.00', 300, 50),
        ],
      );
      expect(draft.lines.single.quantity, 2);
      expect(draft.lines.single.unit, PurchaseUnit.piece);
      expect(draft.lines.single.grossAmountCents, 16800);
      expect(draft.lines.single.description, contains('COFFEE 26G'));
    },
  );

  test(
    'unlabeled multiple prices remain unresolved rather than accepting the wrong column',
    () {
      final draft = parseRows(['Supplier A', 'Coffee 26G 2 84.00 168.00']);
      expect(draft.lines.single.grossAmountCents, isNull);
      expect(
        draft.lines.single.warnings.any(
          (warning) => warning.contains('Multiple prices'),
        ),
        isTrue,
      );
      final wrapped = parseRows(['Supplier A', 'Coffee 26G', '2 84.00 168.00']);
      expect(wrapped.lines.single.grossAmountCents, isNull);
    },
  );

  test(
    'tax markers are accepted while payment footer cannot create extra purchases',
    () {
      final draft = parseRows([
        'Supplier A',
        '2 pcs Coffee 168.00 A',
        'CASH 200.00',
        'Promo sample 10.00',
        'CHANGE 32.00',
      ]);
      expect(draft.lines, hasLength(1));
      expect(draft.lines.single.grossAmountCents, 16800);
    },
  );

  test(
    'ordered pages mark only boundary overlap and retain legitimate repeated rows',
    () {
      ReceiptOcrPage page(String path, List<String> rows) => ReceiptOcrPage(
        imagePath: path,
        textLines: rows.map((text) => OcrTextLine(text: text)).toList(),
      );
      final draft = parser.parsePages(
        pages: [
          page('/page1.jpg', [
            'Supplier A',
            '2026-10-09',
            '1 pcs Milk 40.00',
            '1 pcs Coffee 84.00',
            '1 pcs Coffee 84.00',
          ]),
          page('/page2.jpg', [
            'Supplier A',
            '1 pcs Coffee 84.00',
            '1 pcs Bread 20.00',
            'TOTAL 312.00',
          ]),
        ],
      );
      expect(draft.imagePaths, ['/page1.jpg', '/page2.jpg']);
      expect(draft.lines, hasLength(5));
      expect(
        draft.lines.take(3).every((line) => line.possibleDuplicateOf == null),
        isTrue,
      );
      expect(draft.lines[3].possibleDuplicateOf, draft.lines[2].id);
      expect(draft.lines[3].sourcePage, 1);
      expect(draft.lines[4].possibleDuplicateOf, isNull);
      expect(draft.rawText, contains('--- Photo 2 ---'));
      expect(draft.dateConfirmed, isFalse);
    },
  );

  test(
    'conflicting page metadata requires correction without combining another supplier silently',
    () {
      final draft = parser.parsePages(
        pages: [
          const ReceiptOcrPage(
            imagePath: '/a.jpg',
            textLines: [
              OcrTextLine(text: 'Supplier A'),
              OcrTextLine(text: '2026-10-08'),
              OcrTextLine(text: 'Receipt No 123'),
              OcrTextLine(text: '1 pcs Coffee 84.00'),
            ],
          ),
          const ReceiptOcrPage(
            imagePath: '/b.jpg',
            textLines: [
              OcrTextLine(text: 'Supplier B'),
              OcrTextLine(text: '2026-10-09'),
              OcrTextLine(text: 'Receipt No 456'),
              OcrTextLine(text: '1 pcs Milk 40.00'),
            ],
          ),
        ],
      );
      expect(draft.supplierName, isEmpty);
      expect(draft.purchasedAt, isNull);
      expect(draft.receiptNumber, isEmpty);
      expect(
        draft.warnings.any((warning) => warning.contains('differ')),
        isTrue,
      );
    },
  );
  test(
    'boundary overlap tolerates moved quantity and punctuation while retaining both original rows',
    () {
      final draft = parser.parsePages(
        pages: const [
          ReceiptOcrPage(
            imagePath: '/first.jpg',
            textLines: [
              OcrTextLine(text: 'Supplier A'),
              OcrTextLine(text: 'Brand-X Coffee Original 26G 2 packs 168.00'),
            ],
          ),
          ReceiptOcrPage(
            imagePath: '/second.jpg',
            textLines: [
              OcrTextLine(text: 'Supplier A'),
              OcrTextLine(
                text: '2.00 packs BRAND X COFFEE ORIGINAL 26G 168.00',
              ),
            ],
          ),
        ],
      );
      expect(draft.lines, hasLength(2));
      expect(draft.lines.last.possibleDuplicateOf, draft.lines.first.id);
      expect(
        draft.lines.first.description,
        'Brand-X Coffee Original 26G 2 packs',
      );
      expect(
        draft.lines.last.description,
        '2.00 packs BRAND X COFFEE ORIGINAL 26G',
      );
      expect(
        draft.lines.every((line) => line.grossAmountCents == 16800),
        isTrue,
      );
      expect(draft.lines.every((line) => !line.confirmed), isTrue);
    },
  );

  test(
    'overlap comparison retains product size and internal unit evidence',
    () {
      ReceiptDraft boundary(String earlier, String later) => parser.parsePages(
        pages: [
          ReceiptOcrPage(
            imagePath: '/first.jpg',
            textLines: [
              const OcrTextLine(text: 'Supplier A'),
              OcrTextLine(text: earlier),
            ],
          ),
          ReceiptOcrPage(
            imagePath: '/second.jpg',
            textLines: [
              const OcrTextLine(text: 'Supplier A'),
              OcrTextLine(text: later),
            ],
          ),
        ],
      );
      final differentSize = boundary(
        'Coffee Original 26G 2 packs 168.00',
        '2 packs Coffee Original 30G 168.00',
      );
      expect(differentSize.lines.last.possibleDuplicateOf, isNull);
      final internalUnit = boundary(
        'Milk 2 pcs 500G 168.00',
        '2 pcs Milk 500G 168.00',
      );
      expect(internalUnit.lines.last.possibleDuplicateOf, isNull);
    },
  );

  test(
    'explicit whole decimal quantities map in either description position',
    () {
      final draft = parseRows([
        'Supplier A',
        '2.00 packs Coffee Original 26G 168.00',
        'Milk Original 500G 3.00 pcs 120.00',
        'Coffee 2 packs 10.00 pcs/pack 168.00',
      ]);
      expect(draft.lines[0].quantity, 2);
      expect(draft.lines[0].unit, PurchaseUnit.pack);
      expect(draft.lines[0].grossAmountCents, 16800);
      expect(draft.lines[0].description, contains('Coffee Original 26G'));
      expect(draft.lines[1].quantity, 3);
      expect(draft.lines[1].unit, PurchaseUnit.piece);
      expect(draft.lines[1].grossAmountCents, 12000);
      expect(draft.lines[1].description, contains('Milk Original 500G'));
      expect(draft.lines[2].quantity, 2);
      expect(draft.lines[2].piecesPerPack, 10);
      expect(draft.lines[2].grossAmountCents, 16800);
      final ambiguous = parseRows([
        'Supplier A',
        '2.00 packs Coffee Original 26G 84.00 168.00',
      ]);
      expect(ambiguous.lines.single.quantity, 2);
      expect(ambiguous.lines.single.grossAmountCents, isNull);
    },
  );

  test(
    'fractional quantity suffixes cannot become whole purchase quantities',
    () {
      final draft = parseRows([
        'Supplier A',
        '2.50 packs Coffee Original 26G 168.00',
        'Milk Original 500G 2.50 pcs 120.00',
        'Coffee 2 packs 10.50 pcs/pack 168.00',
      ]);
      expect(draft.lines[0].quantity, isNull);
      expect(draft.lines[0].unit, isNull);
      expect(draft.lines[1].quantity, isNull);
      expect(draft.lines[1].unit, isNull);
      expect(draft.lines[2].quantity, 2);
      expect(draft.lines[2].unit, PurchaseUnit.pack);
      expect(draft.lines[2].piecesPerPack, isNull);
    },
  );
  test(
    'wrapped explicit pack quantity is attached to its product description',
    () {
      final draft = parseRows([
        'SUPPLIER ONE',
        'BRANDX COFFEE 26G',
        '2 PACKS 168.00',
        'TOTAL 168.00',
      ]);
      expect(draft.lines.single.description, contains('BRANDX COFFEE 26G'));
      expect(draft.lines.single.quantity, 2);
      expect(draft.lines.single.unit, PurchaseUnit.pack);
      expect(draft.lines.single.piecesPerPack, isNull);
      expect(draft.lines.single.grossAmountCents, 16800);
    },
  );
}
