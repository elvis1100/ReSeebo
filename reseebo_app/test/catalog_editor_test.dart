import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/services/exact_product_match.dart';
import 'package:reseebo_app/features/catalog/screens/product_editor_screen.dart';
import 'package:reseebo_app/features/catalog/widgets/product_category_field.dart';

class EditorAdapter extends MockReseeboDataAdapter {
  Product? saved;
  @override
  Future<void> saveProduct(Product product) async {
    saved = product;
    await super.saveProduct(product);
  }
}

void main() {
  testWidgets(
    'simplified editing preserves hidden identity and selling values',
    (tester) async {
      final adapter = EditorAdapter();
      final product = (await adapter.getProducts()).first;
      await tester.pumpWidget(
        MaterialApp(
          home: ProductEditorScreen(adapter: adapter, product: product),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Brand'), findsNothing);
      expect(find.text('Variant'), findsNothing);
      expect(find.text('Barcode (optional)'), findsNothing);
      expect(find.text('Selling settings'), findsNothing);
      expect(find.byType(ProductCategoryField), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).first,
        'My full product name',
      );
      await tester.scrollUntilVisible(
        find.text('Save product'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save product'));
      await tester.pumpAndSettle();
      expect(adapter.saved!.name, 'My full product name');
      expect(adapter.saved!.brand, product.brand);
      expect(adapter.saved!.variant, product.variant);
      expect(adapter.saved!.barcode, product.barcode);
      expect(adapter.saved!.markupPercent, product.markupPercent);
      expect(adapter.saved!.sellingPriceCents, product.sellingPriceCents);
      expect(adapter.saved!.size, product.size);
    },
  );

  testWidgets(
    'new products need only full name and size, category is optional',
    (tester) async {
      final adapter = EditorAdapter();
      await tester.pumpWidget(
        MaterialApp(home: ProductEditorScreen(adapter: adapter)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save product'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save product'));
      await tester.pumpAndSettle();
      expect(adapter.saved, isNull);
      await tester.ensureVisible(find.byType(TextFormField).first);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Bear Brand Fortified Milk',
      );
      await tester.enterText(find.byType(TextFormField).at(1), '33g');
      await tester.scrollUntilVisible(
        find.text('Save product'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save product'));
      await tester.pumpAndSettle();
      final product = adapter.saved!;
      expect(product.nameOnly, isTrue);
      expect(product.category, isEmpty);
      expect(product.brand, isEmpty);
      expect(
        exactProductMatch('BearBrandFortifiedMilk33g', [product]),
        product,
      );
      expect(exactProductMatch('Bear Brand Milk 33g', [product]), isNull);
      expect(
        exactProductMatch('Bear Brand Fortified Milk 66g', [product]),
        isNull,
      );
      expect(
        exactProductMatch('Bear Brand Fortified Milk 33g', [
          product,
          product.copyWith(id: 'duplicate'),
        ]),
        isNull,
      );
      expect(exactProductMatch(product.name, [product]), isNull);
    },
  );

  testWidgets('category dropdown adds, selects and removes categories', (
    tester,
  ) async {
    final adapter = EditorAdapter();
    var value = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ProductCategoryField(
              adapter: adapter,
              value: value,
              enabled: true,
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Household');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(value, 'Household');
    expect(await adapter.getProductCategories(), contains('Household'));
    final fieldPosition = tester.getTopLeft(find.byType(InputDecorator).first);
    await tester.tap(find.byTooltip('Choose category'));
    await tester.pumpAndSettle();
    final menuPosition = tester.getTopLeft(find.text('Uncategorized').last);
    await tester.tap(
      find
          .ancestor(
            of: find.text('Uncategorized').last,
            matching: find.byType(CheckedPopupMenuItem<String>),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(value, isEmpty);
    expect(tester.getTopLeft(find.byType(InputDecorator).first), fieldPosition);
    await tester.tap(find.byTooltip('Choose category'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Uncategorized').last), menuPosition);
    await tester.tap(
      find
          .ancestor(
            of: find.text('Household').last,
            matching: find.byType(CheckedPopupMenuItem<String>),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(value, 'Household');
    await tester.tap(find.byTooltip('Remove category'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('purchase history will be kept'),
      findsOneWidget,
    );
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(value, isEmpty);
    expect(await adapter.getProductCategories(), isNot(contains('Household')));
    expect(tester.takeException(), isNull);
  });
}
