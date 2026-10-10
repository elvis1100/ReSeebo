import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/widgets/app_card.dart';
import 'package:reseebo_app/features/comparison/screens/product_comparison_screen.dart';
import 'package:reseebo_app/features/comparison/widgets/supplier_comparison_table.dart';
import 'package:reseebo_app/features/receipt_scan/screens/review_match_screen.dart';
import 'package:reseebo_app/features/receipts/screens/receipt_detail_screen.dart';
import 'package:reseebo_app/features/receipts/state/pending_receipt_controller.dart';
import 'package:reseebo_app/features/receipts/widgets/receipt_revision_history.dart';
import 'package:reseebo_app/features/receipts/widgets/saved_digital_receipt.dart';

import 'fixtures/receipt_ledger_ui_fixture.dart';

void main() {
  testWidgets(
    'return from receipt details refreshes the confirmed comparison',
    (tester) async {
      final adapter = LedgerUiAdapter();
      await adapter.seedConfirmed();
      await tester.pumpWidget(
        ledgerApp(
          ProductComparisonScreen(
            dataAdapter: adapter,
            productId: ledgerProduct.id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final card = find
          .descendant(
            of: find.byType(SupplierComparisonTable),
            matching: find.byType(AppCard),
          )
          .first;
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptDetailScreen), findsOneWidget);
      final beforeReturn = adapter.comparisonReads;
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        adapter.comparisonReads,
        greaterThan(beforeReturn),
        reason:
            'A saved correction must be reflected when returning to prices.',
      );
    },
  );

  testWidgets('confirmed_edit_creates_pending_correction', (tester) async {
    final adapter = LedgerUiAdapter();
    final saved = await adapter.seedConfirmed();
    PendingSaveResult? correction;
    await tester.pumpWidget(
      ledgerApp(
        ReceiptDetailScreen(
          adapter: adapter,
          receiptId: saved.receiptId,
          onPendingReceiptSaved: (value) => correction = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SavedDigitalReceipt), findsOneWidget);
    await tapLedgerText(tester, 'Edit receipt');
    final review = tester.widget<ReviewMatchScreen>(
      find.byType(ReviewMatchScreen),
    );
    expect(review.correctionOfReceiptId, saved.receiptId);
    expect(review.expectedConfirmedRevision, 1);
    expect(review.initialDraft.lines.single.grossAmountCents, 2400);
    await tester.ensureVisible(find.byKey(const ValueKey('amount')));
    await tester.enterText(find.byKey(const ValueKey('amount')), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tapLedgerText(tester, 'Save Needs review');
    expect(correction, isNotNull);
    final pending = await adapter.getPendingReceipt(correction!.id);
    expect(pending.correctionOfReceiptId, saved.receiptId);
    expect(pending.baseConfirmedRevision, 1);
    expect(pending.draft.lines.single.grossAmountCents, isNull);
    expect(
      pending
          .draft
          .lines
          .single
          .provenance[ReceiptSuggestionField.amount]!
          .origin,
      ReceiptFieldOrigin.ownerEdited,
    );
    expect(
      (await adapter.getReceipt(saved.receiptId)).receipt.totalCents,
      2400,
    );
    final entries = (await adapter.getLedgerEntries())
        .where((entry) => entry.confirmedReceiptId == saved.receiptId)
        .toList();
    expect(entries, hasLength(1));
    expect(entries.single.pendingId, correction!.id);
    expect(adapter.directConfirmedWrites, 0);
  });

  test('confirm_routes_to_same_entry and archives prior values', () async {
    final adapter = LedgerUiAdapter();
    final saved = await adapter.seedConfirmed();
    final original = await adapter.getReceipt(saved.receiptId);
    final edit = await adapter.getConfirmedReceiptEdit(saved.receiptId);
    final correctionDraft = edit.draft;
    correctionDraft.lines.single.grossAmountCents = 1300;
    correctionDraft.detectedTotalCents = 1300;
    correctionDraft.notes = 'Corrected final price';
    final pending = await adapter.savePendingReceipt(
      correctionDraft,
      operationId: 'create-correction',
      correctionOfReceiptId: saved.receiptId,
      expectedConfirmedRevision: 1,
    );
    final controller = PendingReceiptController(adapter);
    addTearDown(controller.dispose);
    await controller.load(pending.id);
    final result = await controller.confirm();
    expect(result.receiptId, saved.receiptId);
    final current = await adapter.getReceipt(saved.receiptId);
    expect(current.receipt.totalCents, 1300);
    expect(current.receipt.createdAt, original.receipt.createdAt);
    expect(current.lines.single.id, original.lines.single.id);
    final revisions = await adapter.getReceiptRevisions(saved.receiptId);
    expect(revisions, hasLength(1));
    expect(revisions.single.revision, 1);
    expect(revisions.single.draft.lines.single.grossAmountCents, 2400);
    expect(revisions.single.draft.imagePaths, [
      'owned/original-1.png',
      'owned/original-2.png',
    ]);
    expect(
      await adapter.resolveConfirmedReceiptId(pending.id),
      saved.receiptId,
    );
  });

  testWidgets('confirmed detail remains readable while correction is pending', (
    tester,
  ) async {
    final adapter = LedgerUiAdapter();
    final saved = await adapter.seedConfirmed();
    final edit = await adapter.getConfirmedReceiptEdit(saved.receiptId);
    await adapter.savePendingReceipt(
      edit.draft..lines.single.grossAmountCents = null,
      operationId: 'unresolved-correction',
      correctionOfReceiptId: saved.receiptId,
      expectedConfirmedRevision: edit.revision,
    );
    await tester.pumpWidget(
      ledgerApp(
        ReceiptDetailScreen(adapter: adapter, receiptId: saved.receiptId),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SavedDigitalReceipt), findsOneWidget);
    expect(find.text('RECORDED TOTAL'), findsOneWidget);
    expect(find.text('₱24.00'), findsWidgets);
    expect(find.text('Edit receipt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history_shows_prior_values with original photo access', (
    tester,
  ) async {
    final revision = ReceiptRevision(
      revision: 1,
      recordedAt: DateTime(2026, 10, 10),
      draft: ledgerDraft(complete: true),
    );
    await tester.pumpWidget(
      ledgerApp(
        Scaffold(
          body: SingleChildScrollView(
            child: ReceiptRevisionHistory(revisions: [revision]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tapLedgerText(tester, 'Revision 1');
    expect(find.textContaining('Brand X Original Coffee 26g'), findsWidgets);
    expect(find.text('₱24.00'), findsWidgets);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Confirm receipt'), findsNothing);
    await tapLedgerText(tester, 'Photo 2');
    expect(find.text('Original receipt · Photo 2'), findsOneWidget);
    revision.draft.lines.single.grossAmountCents = 9999;
    expect(revision.draft.lines.single.grossAmountCents, 2400);
  });

  for (final width in [360.0, 412.0]) {
    testWidgets('confirmed detail and history fit ${width}dp at text scale 2', (
      tester,
    ) async {
      ledgerPhone(tester, width);
      final adapter = LedgerUiAdapter();
      final saved = await adapter.seedConfirmed();
      final edit = await adapter.getConfirmedReceiptEdit(saved.receiptId);
      final corrected = edit.draft;
      corrected.lines.single.grossAmountCents = 1300;
      corrected.detectedTotalCents = 1300;
      final pending = await adapter.savePendingReceipt(
        corrected,
        operationId: 'layout-correction',
        correctionOfReceiptId: saved.receiptId,
        expectedConfirmedRevision: 1,
      );
      await adapter.confirmPendingReceipt(
        pending.id,
        expectedRevision: pending.revision,
        operationId: 'confirm-layout-correction',
      );
      await tester.pumpWidget(
        ledgerApp(
          ReceiptDetailScreen(adapter: adapter, receiptId: saved.receiptId),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      await revealLedgerFinder(tester, find.text('Revision 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revision 1'));
      await tester.pumpAndSettle();
      expect(find.text('₱24.00'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
