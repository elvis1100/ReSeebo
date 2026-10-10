import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/services/exact_product_match.dart';
import 'package:reseebo_app/core/services/receipt_parser.dart';
import 'package:reseebo_app/core/services/receipt_product_match.dart';
import 'package:reseebo_app/core/services/starter_catalog_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('report actual public OCR matching against bundled catalog', () async {
    final products = await StarterCatalogService.load();
    for (final name in [
      'dali_enhanced',
      'waltermart_enhanced',
      'savemore_enhanced',
    ]) {
      final data =
          jsonDecode(
                File(
                  'test/fixtures/public_receipts/$name.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final draft = ReceiptParser().parse(
        imagePath: '/$name',
        textLines: [
          for (final row in data['lines'] as List)
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
        ],
      );
      final exact = draft.lines
          .where(
            (line) => exactProductMatch(line.description, products) != null,
          )
          .length;
      final abbreviation = draft.lines
          .where(
            (line) => receiptProductMatch(line.description, products) != null,
          )
          .length;
      // ignore: avoid_print
      print(
        'BUNDLED_MATCH $name: ${draft.lines.length} rows; exact $exact; abbreviation $abbreviation',
      );
      expect(draft.lines.every((line) => !line.confirmed), isTrue);
    }
  });
  test('controlled abbreviation before and after uses the same catalog', () {
    const products = [
      Product(
        id: 'milk',
        name: 'Bear Brand Fortified Milk',
        brand: '',
        variant: '',
        size: '33g',
        nameOnly: true,
      ),
      Product(
        id: 'tang',
        name: 'Tang Powder Mango',
        brand: '',
        variant: '',
        size: '19g',
        nameOnly: true,
      ),
    ];
    for (final description in ['BB FORT MILK33G', 'TangPwdrMango19g']) {
      expect(exactProductMatch(description, products), isNull);
      expect(receiptProductMatch(description, products), isNotNull);
    }
  });
}
