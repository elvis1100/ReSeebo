import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/features/receipt_scan/state/receipt_review_state.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/services/receipt_product_match.dart';

Product item(String id, String name, String size) => Product(
  id: id,
  name: name,
  brand: '',
  variant: '',
  size: size,
  nameOnly: true,
);

class MatchAdapter extends MockReseeboDataAdapter {
  MatchAdapter(this.products);
  final List<Product> products;
  @override
  Future<List<Product>> getProducts({String? query}) async => products;
  @override
  Future<List<ProductMatchSuggestion>> matchAliases(
    String description, {
    String? supplierId,
  }) async => [];
}

void main() {
  test('counted sizes work and unrelated numeric identity is retained', () {
    final eggs = item('eggs', 'HappiNest Fresh Egg Extra Large', '12s');
    expect(
      receiptProductMatch('HappiNest Fresh Egg Extra Large 12s', [eggs]),
      eggs,
    );
    final coffee = item('coffee', 'Coffee 3in1', '26g');
    expect(receiptProductMatch('Coffee 3in1 26g 4', [coffee]), isNull);
  });
  final milk = item('milk', 'Bear Brand Fortified Milk', '33g');
  final tang = item('tang', 'Tang Powder Mango', '19g');
  test('brand initials and shortened variant fill unique product', () {
    expect(receiptProductMatch('BB FORT MILK33G', [milk])?.id, 'milk');
  });
  test('joined consonant abbreviations fill actual receipt style', () {
    expect(receiptProductMatch('TangPwdrMango19g', [tang])?.id, 'tang');
  });
  test('one spelling error allowed for longer identity words', () {
    expect(receiptProductMatch('Tang Powder Mangoo 19g', [tang])?.id, 'tang');
  });
  test('wrong sizes and digits never repaired', () {
    expect(receiptProductMatch('BB FORT MILK 38g', [milk]), isNull);
    expect(receiptProductMatch('BB FORT MILK 33g 80g', [milk]), isNull);
    expect(receiptProductMatch('BB FORT MILK', [milk]), isNull);
    expect(receiptProductMatch('BB FORT MILK 33g 2', [milk]), isNull);
    expect(
      receiptProductMatch('Bear Brand Fortified Milk Chocolate 33g', [milk]),
      isNull,
    );
  });
  test('missing and competing variants and duplicates remain choices', () {
    final orange = item('orange', 'Tang Powder Orange', '19g');
    expect(receiptProductMatch('Tang Pwdr 19g', [tang, orange]), isNull);
    expect(
      receiptProductMatch('Tang Pwdr Orange 19g', [tang, orange])?.id,
      'orange',
    );
    expect(
      receiptProductMatch('BB FORT MILK 33g', [
        milk,
        milk.copyWith(id: 'duplicate'),
      ]),
      isNull,
    );
    expect(receiptProductMatch('BB FORT CHOC MILK 33g', [milk]), isNull);
  });
  test('metric equivalent size and partial suggestions', () {
    final oil = item('oil', 'UFC Golden Fiesta Canola Oil', '1L');
    expect(
      receiptProductMatch('UFC Gold Fies Canola Oil 1000ml', [oil])?.id,
      'oil',
    );
    expect(
      receiptProductSuggestions('Tang Powder 19g', [tang]).single.product.id,
      'tang',
    );
    expect(receiptProductSuggestions('Tang Powder 20g', [tang]), isEmpty);
  });
  test(
    'review automatically fills abbreviations but never confirms purchase',
    () async {
      final state = ReceiptReviewState(
        adapter: MatchAdapter([milk]),
        draft: ReceiptDraft(
          lines: [ParsedLineItem(description: 'BB FORT MILK33G')],
        ),
      );
      await state.load();
      final line = state.draft.lines.single;
      expect(line.productId, 'milk');
      expect(line.confirmed, isFalse);
      state.editText(line, ReceiptLineField.description, 'BB FORT MILK38G');
      expect(line.productId, isNull);
      state.dispose();
    },
  );
}
