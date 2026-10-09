import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/theme/app_theme.dart';
import 'package:reseebo_app/features/receipt_scan/widgets/receipt_metadata_editor.dart';

void main() {
  testWidgets(
    'optional details keep their values when hidden; branch edits detach saved supplier',
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
      expect(find.text('Branch: Main branch'), findsOneWidget);
      expect(find.text('Receipt number (optional)'), findsNothing);
      expect(draft.receiptNumber, 'R-123');
      expect(draft.dateConfirmed, isTrue);

      await tester.ensureVisible(find.text('More details'));
      await tester.tap(find.text('More details'));
      await tester.pumpAndSettle();
      expect(find.text('Receipt number (optional)'), findsOneWidget);
      final branch = find.widgetWithText(
        TextFormField,
        'Branch / location (optional)',
      );
      await tester.ensureVisible(branch);
      await tester.enterText(branch, 'Other branch');
      expect(draft.supplierBranch, 'Other branch');
      expect(draft.supplierId, isNull);
      expect(draft.dateConfirmed, isTrue);
      expect(changes, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
