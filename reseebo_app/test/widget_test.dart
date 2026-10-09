import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:reseebo_app/core/widgets/store_header.dart';
import 'package:reseebo_app/main.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';

void main() {
  testWidgets('ReseeboApp boots and renders offline dashboard', (
    WidgetTester tester,
  ) async {
    // Build Reseebo and trigger a frame.
    await tester.pumpWidget(const ReseeboApp());
    await tester.pumpAndSettle();

    // Verify that the title and core dashboard controls are rendered.
    expect(find.text('Reseebo'), findsOneWidget);
    expect(find.text('Scan Receipt'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FloatingActionButton),
        matching: find.text('Scan Receipt'),
      ),
      findsOneWidget,
    );
    final headerText = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(StoreHeader),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data);
    expect(headerText, ['Reseebo']);
    expect(find.byTooltip('Refresh data'), findsOneWidget);
    expect(find.text('Add product').hitTestable(), findsNothing);
    await tester.tap(find.text('Products (4)'));
    await tester.pumpAndSettle();
    expect(find.text('Add product').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Recent Receipts (4)'));
    await tester.pumpAndSettle();
    expect(find.text('Add product').hitTestable(), findsNothing);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(StoreHeader),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data),
      ['Reseebo'],
    );
    expect(find.byTooltip('Refresh settings'), findsOneWidget);
  });
  testWidgets(
    'saving settings preserves an existing hidden logo and zero markup',
    (tester) async {
      final adapter = MockReseeboDataAdapter();
      await adapter.updateStoreProfile(
        const StoreProfile(
          name: 'Original store',
          photoPath: 'existing-store-logo.jpg',
          defaultMarkupPercent: 0,
        ),
      );
      await tester.pumpWidget(ReseeboApp(dataAdapter: adapter));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Store logo (optional)'), findsNothing);
      expect(find.byTooltip('Choose store logo'), findsNothing);
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Store name',
        ),
        'Updated store',
      );
      await tester.ensureVisible(find.text('Save settings'));
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      final saved = await adapter.getStoreProfile();
      expect(saved.storeName, 'Updated store');
      expect(saved.photoPath, 'existing-store-logo.jpg');
      expect(saved.defaultMarkupPercent, 0);
    },
  );
}
