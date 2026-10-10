import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/models/pending_receipt.dart';
import 'package:reseebo_app/features/receipt_scan/screens/capture_screen.dart';
import 'package:reseebo_app/features/receipt_scan/screens/review_match_screen.dart';
import 'package:reseebo_app/main.dart';

Future<CaptureScreen> openCapture(
  WidgetTester tester, {
  MockReseeboDataAdapter? adapter,
}) async {
  await tester.pumpWidget(
    ReseeboApp(dataAdapter: adapter ?? MockReseeboDataAdapter()),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Get started'));
  await tester.tap(find.text('Get started'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan Receipt'));
  await tester.pumpAndSettle();
  return tester.widget<CaptureScreen>(find.byType(CaptureScreen));
}

void main() {
  testWidgets('prepared capture proposals survive entering Review', (
    tester,
  ) async {
    final adapter = MockReseeboDataAdapter();
    final product = (await adapter.getProducts()).first;
    final supplier = (await adapter.getSuppliers()).first;
    final importedDate = DateTime(2024, 1, 2);
    final original = ReceiptDraft(
      imagePaths: [],
      supplierId: supplier.id,
      supplierName: supplier.name,
      purchasedAt: importedDate,
      detectedTotalCents: 3333,
      provenance: {
        ReceiptMetadataField.purchasedAt: const ReceiptFieldProvenance(
          origin: ReceiptFieldOrigin.assumed,
          explanation: 'Original import date proposal.',
        ),
      },
      lines: [
        ParsedLineItem(
          productId: product.id,
          description: product.name,
          quantity: 1,
          unit: PurchaseUnit.piece,
          piecesPerPack: 1,
          grossAmountCents: 3333,
          provenance: {
            ReceiptSuggestionField.amount: const ReceiptFieldProvenance(
              origin: ReceiptFieldOrigin.history,
              explanation: 'Previously prepared confirmed-price proposal.',
            ),
          },
        ),
      ],
    );
    final capture = await openCapture(tester, adapter: adapter);
    final returned = capture.onReviewRequested!(original);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_rounded).last);
    await tester.pumpAndSettle();
    final edited = (await returned)!;
    expect(edited.purchasedAt, importedDate);
    expect(edited.lines.single.grossAmountCents, 3333);
    expect(
      edited
          .lines
          .single
          .provenance[ReceiptSuggestionField.amount]!
          .explanation,
      'Previously prepared confirmed-price proposal.',
    );
    expect(find.byType(CaptureScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review back returns owner edits and retains capture route', (
    tester,
  ) async {
    final capture = await openCapture(tester);
    final original = ReceiptDraft(
      supplierName: 'Original store',
      imagePaths: [],
    );
    final returned = capture.onReviewRequested!(original);
    await tester.pumpAndSettle();
    final supplierField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.controller?.text == 'Original store',
    );
    expect(supplierField, findsOneWidget);
    await tester.ensureVisible(supplierField);
    await tester.enterText(supplierField, 'Owner corrected store');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_rounded).last);
    await tester.pumpAndSettle();
    final edited = await returned;
    expect(edited!.supplierName, 'Owner corrected store');
    expect(original.supplierName, 'Original store');
    expect(find.byType(CaptureScreen), findsOneWidget);
    expect(find.byType(ReviewMatchScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending save in review closes both receipt routes', (
    tester,
  ) async {
    final capture = await openCapture(tester);
    final returned = capture.onReviewRequested!(ReceiptDraft(imagePaths: []));
    await tester.pumpAndSettle();
    tester
        .widget<ReviewMatchScreen>(find.byType(ReviewMatchScreen))
        .onPendingSaved!(const PendingSaveResult(id: 'saved', revision: 1));
    await tester.pumpAndSettle();
    expect(await returned, isNull);
    expect(find.byType(CaptureScreen), findsNothing);
    expect(find.byType(ReviewMatchScreen), findsNothing);
    expect(find.text('Scan Receipt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
