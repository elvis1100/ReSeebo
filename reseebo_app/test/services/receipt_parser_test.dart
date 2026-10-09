import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/services/receipt_parser.dart';

void main() {
  final parser = ReceiptParser();

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
          (warning) => warning.contains('already includes'),
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
