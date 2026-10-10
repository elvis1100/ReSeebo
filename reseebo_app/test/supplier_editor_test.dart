import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/features/suppliers/screens/supplier_editor_screen.dart';

class _SupplierAdapter extends MockReseeboDataAdapter {
  Supplier? saved;
  @override
  Future<void> saveSupplier(Supplier supplier) async => saved = supplier;
}

void main() {
  for (final existing in [false, true]) {
    testWidgets(
      '${existing ? 'editing' : 'adding'} supplier hides branch and preserves its stored identity',
      (tester) async {
        final adapter = _SupplierAdapter();
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SupplierEditorScreen(
                        adapter: adapter,
                        supplier: existing
                            ? const Supplier(
                                id: 'saved',
                                name: 'Grocer',
                                branch: 'North',
                                notes: 'Cash',
                              )
                            : null,
                      ),
                    ),
                  ),
                  child: const Text('Open supplier'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open supplier'));
        await tester.pumpAndSettle();
        expect(find.text('Branch / location (optional)'), findsNothing);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Supplier name'),
          'Updated grocer',
        );
        await tester.tap(find.text('Save supplier'));
        await tester.pumpAndSettle();
        expect(adapter.saved!.name, 'Updated grocer');
        expect(adapter.saved!.branch, existing ? 'North' : '');
        if (existing) expect(adapter.saved!.id, 'saved');
        expect(find.text('Open supplier'), findsOneWidget);
      },
    );
  }
}
