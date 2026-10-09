import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/features/receipt_scan/widgets/line_item_editor_row.dart';
import 'package:reseebo_app/core/theme/app_colors.dart';

void main() {
  testWidgets('item entry has cost and no discount controls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LineItemEditorRow(
              line: ParsedLineItem(unit: PurchaseUnit.piece, piecesPerPack: 1),
              index: 0,
              onSelectProduct: () {},
              onQuantityChanged: (_) {},
              onPiecesPerPackChanged: (_) {},
              onLineTotalChanged: (_) {},
              onRemove: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Cost (₱)'), findsOneWidget);
    expect(find.text('Discount (₱)'), findsNothing);
    expect(find.byKey(const ValueKey('discount')), findsNothing);
    expect(find.text('Receipt details'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text('Check brand, variant and size'), findsNothing);
    final description = tester.getRect(
      find.byKey(const ValueKey('description')),
    );
    final amount = tester.getRect(find.byKey(const ValueKey('amount')));
    expect(description.bottom, lessThan(amount.top));
    expect(description.width, greaterThan(amount.width));
    expect(
      tester.widget<Icon>(find.byIcon(Icons.delete_outline_rounded)).color,
      AppColors.danger,
    );
  });

  testWidgets(
    'item warning section and copying tools are absent while validation stays visible',
    (tester) async {
      final line = ParsedLineItem(
        description: 'Coffee',
        quantity: 2,
        warnings: ['Several prices found. Check the line amount.'],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LineItemEditorRow(
                line: line,
                problem: 'Enter the total amount paid for this item.',
                index: 0,
                onSelectProduct: () {},
                onQuantityChanged: (_) {},
                onPiecesPerPackChanged: (_) {},
                onLineTotalChanged: (_) {},
                onRemove: () {},
              ),
            ),
          ),
        ),
      );
      expect(
        find.text('Several prices found. Check the line amount.'),
        findsNothing,
      );
      expect(find.text('Check these details'), findsNothing);
      expect(
        find.text('Enter the total amount paid for this item.'),
        findsOneWidget,
      );
      expect(find.text('Copy a value from the receipt'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byKey(const ValueKey('description')), findsOneWidget);
    },
  );
  testWidgets(
    'item fields retain a matte green fill before and after confirmation',
    (tester) async {
      final line = ParsedLineItem(description: 'Coffee', quantity: 2);
      Widget host() => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LineItemEditorRow(
              line: line,
              index: 0,
              onSelectProduct: () {},
              onQuantityChanged: (_) {},
              onPiecesPerPackChanged: (_) {},
              onLineTotalChanged: (_) {},
              onRemove: () {},
            ),
          ),
        ),
      );
      await tester.pumpWidget(host());
      TextField quantityField() => tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('quantity')),
          matching: find.byType(TextField),
        ),
      );
      final quantity = quantityField();
      expect(quantity.decoration!.filled, isTrue);
    expect(quantity.decoration!.fillColor, AppColors.fieldSurface);
      line.confirmed = true;
      await tester.pumpWidget(host());
      expect(quantityField().decoration!.filled, isTrue);
    expect(quantityField().decoration!.fillColor, AppColors.fieldSurface);
    },
  );
  testWidgets('external draft update refreshes an unfocused quantity editor', (
    tester,
  ) async {
    final line = ParsedLineItem(description: 'Coffee', quantity: 2);
    Widget host() => MaterialApp(
      home: Scaffold(
        body: LineItemEditorRow(
          key: ValueKey(line.id),
          line: line,
          index: 0,
          onSelectProduct: () {},
          onQuantityChanged: (_) {},
          onPiecesPerPackChanged: (_) {},
          onLineTotalChanged: (_) {},
          onRemove: () {},
        ),
      ),
    );
    await tester.pumpWidget(host());
    line.quantity = 12;
    await tester.pumpWidget(host());
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('quantity')),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.controller.text, '12');
  });
}
