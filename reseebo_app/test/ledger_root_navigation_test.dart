import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/features/dashboard/screens/dashboard_screen.dart';
import 'package:reseebo_app/features/receipts/screens/pending_receipt_screen.dart';
import 'package:reseebo_app/features/receipts/screens/receipt_detail_screen.dart';
import 'package:reseebo_app/main.dart';

import 'fixtures/receipt_ledger_ui_fixture.dart';

Future<void> enterLedger(WidgetTester tester, LedgerUiAdapter adapter) async {
  await tester.pumpWidget(ReseeboApp(dataAdapter: adapter));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Get started'));
  await tester.tap(find.text('Get started'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('root opens pending entry and refreshes ledger after returning', (
    tester,
  ) async {
    final adapter = LedgerUiAdapter();
    final saved = await adapter.seedPending(
      draft: ledgerDraft(photosOnly: true),
    );
    await enterLedger(tester, adapter);
    final before = tester.widget<DashboardScreen>(find.byType(DashboardScreen));
    before.onPendingReceiptSelected!(saved.id);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PendingReceiptScreen>(find.byType(PendingReceiptScreen))
          .pendingId,
      saved.id,
    );
    Navigator.of(tester.element(find.byType(PendingReceiptScreen))).pop();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DashboardScreen>(find.byType(DashboardScreen))
          .refreshRevision,
      greaterThan(before.refreshRevision),
    );
    expect(adapter.ocrReads, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('root correction callback opens saved pending receipt', (
    tester,
  ) async {
    final adapter = LedgerUiAdapter();
    final confirmed = await adapter.seedConfirmed();
    final editable = await adapter.getConfirmedReceiptEdit(confirmed.receiptId);
    final pending = await adapter.savePendingReceipt(
      editable.draft,
      operationId: 'root-correction',
      correctionOfReceiptId: confirmed.receiptId,
      expectedConfirmedRevision: editable.revision,
    );
    final detail = await adapter.getReceipt(confirmed.receiptId);
    await enterLedger(tester, adapter);
    tester
        .widget<DashboardScreen>(find.byType(DashboardScreen))
        .onReceiptSelected!(detail.receipt);
    await tester.pumpAndSettle();
    final opened = tester
        .widget<ReceiptDetailScreen>(find.byType(ReceiptDetailScreen))
        .onOpenPendingReceipt!(pending.id);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PendingReceiptScreen>(find.byType(PendingReceiptScreen))
          .pendingId,
      pending.id,
    );
    expect(adapter.ocrReads, 0);
    Navigator.of(tester.element(find.byType(PendingReceiptScreen))).pop();
    await tester.pumpAndSettle();
    await opened;
    expect(find.byType(ReceiptDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
