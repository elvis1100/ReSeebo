import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/features/receipt_scan/widgets/line_item_editor_row.dart';
import 'package:reseebo_app/core/theme/app_colors.dart';

void main() {
  testWidgets(
    'parser evidence warnings remain visible beside editable values',
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
        findsOneWidget,
      );
    },
  );
  testWidgets('unconfirmed OCR quantity stays amber until owner checks it', (
    tester,
  ) async {
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
    expect(quantity.decoration!.fillColor, AppColors.warningBg);
    line.confirmed = true;
    await tester.pumpWidget(host());
    expect(quantityField().decoration!.filled, isFalse);
  });
  testWidgets('external assignment updates the visible quantity editor', (
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
