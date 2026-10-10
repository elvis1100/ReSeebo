import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:reseebo_app/core/adapters/i_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/features/receipt_scan/screens/review_match_screen.dart';

import 'fixtures/receipt_scan_widget_fixture.dart';

/// Observes submitted commands without replacing duplicate checks, pending
/// persistence, revision checks, or confirmation in the production mock adapter.
class _ObservedReceiptAdapter extends MockReseeboDataAdapter {
  final pendingCommands = <String>[];
  final submittedDrafts = <ReceiptDraft>[];
  final confirmedRevisions = <int>[];

  @override
  Future<PendingSaveResult> savePendingReceipt(
    ReceiptDraft draft, {
    required String operationId,
    String? pendingId,
    int? expectedRevision,
    String? correctionOfReceiptId,
    int? expectedConfirmedRevision,
  }) {
    pendingCommands.add(operationId);
    submittedDrafts.add(draft.snapshot());
    return super.savePendingReceipt(
      draft,
      operationId: operationId,
      pendingId: pendingId,
      expectedRevision: expectedRevision,
      correctionOfReceiptId: correctionOfReceiptId,
      expectedConfirmedRevision: expectedConfirmedRevision,
    );
  }

  @override
  Future<SaveReceiptResult> confirmPendingReceipt(
    String id, {
    required int expectedRevision,
    required String operationId,
  }) {
    confirmedRevisions.add(expectedRevision);
    return super.confirmPendingReceipt(
      id,
      expectedRevision: expectedRevision,
      operationId: operationId,
    );
  }
}

void main() {
  for (final correction in [false, true]) {
    testWidgets(
      '${correction ? 'correction' : 'pending'} confirmation duplicate approval replaces the rejected frozen command',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync('duplicate-ui-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final photo = File('${directory.path}/receipt.png')
          ..writeAsBytesSync(image.encodePng(image.Image(width: 3, height: 7)));
        final adapter = _ObservedReceiptAdapter();
        var draft = ReceiptDraft(
          operationId: 'owner-original',
          imagePath: photo.path,
          supplierName: 'Duplicate Test Shop',
          purchasedAt: DateTime(2026, 10, 9),
          dateConfirmed: true,
          lines: [
            ParsedLineItem(
              id: 'owner-line',
              description: 'Coffee original 26g',
              quantity: 2,
              unit: PurchaseUnit.piece,
              piecesPerPack: 1,
              grossAmountCents: 4200,
              confirmed: true,
            ),
          ],
        );
        String? sourceId;
        if (correction) {
          sourceId = (await adapter.saveConfirmedReceipt(draft)).receiptId;
          draft = (await adapter.getConfirmedReceiptEdit(sourceId)).draft;
          draft.lines.single.grossAmountCents = 5200;
        }
        final pending = await adapter.savePendingReceipt(
          draft,
          operationId: 'initial-pending',
          correctionOfReceiptId: sourceId,
          expectedConfirmedRevision: correction ? 1 : null,
        );
        final competing = draft.snapshot()..allowDuplicate = true;
        await adapter.savePendingReceipt(competing, operationId: 'competing');
        adapter.pendingCommands.clear();
        adapter.submittedDrafts.clear();
        final before = (await adapter.getRecentReceipts()).length;
        SaveReceiptResult? completed;

        await tester.pumpWidget(
          scanApp(
            ReviewMatchScreen(
              dataAdapter: adapter,
              initialDraft: draft,
              pendingId: pending.id,
              expectedRevision: pending.revision,
              correctionOfReceiptId: sourceId,
              expectedConfirmedRevision: correction ? 1 : null,
              onConfirmPending: (review) async {
                final saved = await review.savePending();
                return adapter.confirmPendingReceipt(
                  saved.id,
                  expectedRevision: saved.revision,
                  operationId: 'owner-confirmation',
                );
              },
              onSaved: (result) => completed = result,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue to save'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Save receipt'));
        await tester.pumpAndSettle();
        expect(find.text('Possible duplicate receipt'), findsOneWidget);
        expect(adapter.submittedDrafts.single.allowDuplicate, isFalse);
        expect(adapter.confirmedRevisions, isEmpty);

        await tester.tap(find.text('This is a separate purchase'));
        await tester.pumpAndSettle();
        expect(adapter.submittedDrafts.map((draft) => draft.allowDuplicate), [
          false,
          true,
        ]);
        expect(adapter.pendingCommands, hasLength(2));
        expect(
          adapter.pendingCommands.last,
          isNot(adapter.pendingCommands.first),
        );
        expect(adapter.pendingCommands.last, isNot(draft.operationId));
        expect(adapter.confirmedRevisions, [2]);
        expect(completed, isNotNull);
        expect(find.text('Possible duplicate receipt'), findsNothing);
        expect(
          await adapter.resolveConfirmedReceiptId(pending.id),
          completed!.receiptId,
        );
        expect(
          (await adapter.getRecentReceipts()).length,
          before + (correction ? 0 : 1),
        );
        final confirmed = await adapter.getConfirmedReceiptEdit(
          completed!.receiptId,
        );
        expect(
          confirmed.draft.lines.single.grossAmountCents,
          correction ? 5200 : 4200,
        );
        expect(confirmed.revision, correction ? 2 : 1);
        if (correction) expect(completed!.receiptId, sourceId);
        expect(
          draft.allowDuplicate,
          isFalse,
          reason: 'The caller snapshot stays private.',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
