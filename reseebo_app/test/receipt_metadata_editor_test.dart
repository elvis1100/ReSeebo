import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/theme/app_theme.dart';
import 'package:reseebo_app/features/receipt_scan/widgets/receipt_metadata_editor.dart';

void main() {
  testWidgets(
    'hidden optional metadata and date edits preserve hidden branch; name edits detach its saved identity',
    (tester) async {
      final draft = ReceiptDraft(
        supplierId: 'saved-supplier',
        supplierName: 'Grocery store',
        supplierBranch: 'Main branch',
        purchasedAt: DateTime(2026, 10, 9),
        dateConfirmed: true,
        receiptNumber: 'R-123',
        notes: 'Paid cash',
      );
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ReceiptMetadataEditor(
                  draft: draft,
                  suppliers: const [],
                  onChanged: () => changes++,
                  onEditSupplier: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Supplier name'), findsOneWidget);
      expect(find.text('Purchase date'), findsOneWidget);
      expect(find.text('Branch: Main branch'), findsNothing);
      expect(find.text('Branch / location (optional)'), findsNothing);
      expect(find.text('Receipt number (optional)'), findsNothing);
      expect(find.text('Receipt notes (optional)'), findsNothing);
      expect(find.text('Add purchase time'), findsNothing);
      expect(find.byIcon(Icons.schedule_outlined), findsNothing);
      expect(find.text('More details'), findsNothing);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(draft.receiptNumber, 'R-123');
      expect(draft.dateConfirmed, isTrue);

      expect(find.text('Receipt number (optional)'), findsNothing);
      expect(draft.notes, 'Paid cash');
      await tester.ensureVisible(find.text('I checked the purchase date'));
      await tester.tap(find.text('I checked the purchase date'));
      expect(draft.supplierBranch, 'Main branch');
      expect(draft.supplierId, 'saved-supplier');
      final name = find.widgetWithText(TextFormField, 'Supplier name');
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Other grocery');
      expect(draft.supplierBranch, isEmpty);
      expect(draft.supplierId, isNull);
      expect(changes, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'saved supplier picker keeps branch identities without a branch input',
    (tester) async {
      final draft = ReceiptDraft(supplierName: 'Grocer');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReceiptMetadataEditor(
                draft: draft,
                suppliers: const [
                  Supplier(id: 'main', name: 'Grocer', branch: 'Main'),
                  Supplier(id: 'north', name: 'Grocer', branch: 'North'),
                ],
                onChanged: () {},
                onEditSupplier: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Saved suppliers'));
      await tester.pumpAndSettle();
      expect(find.text('Choose supplier'), findsOneWidget);
      expect(find.text('Grocer · Main'), findsOneWidget);
      expect(find.text('Grocer · North'), findsOneWidget);
      await tester.tap(find.text('Grocer · North'));
      await tester.pumpAndSettle();
      expect(draft.supplierId, 'north');
      expect(draft.supplierBranch, 'North');
      expect(find.text('Branch: North'), findsNothing);
      expect(find.text('Branch / location (optional)'), findsNothing);
    },
  );
}
