import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/features/dashboard/screens/dashboard_screen.dart';
import 'package:reseebo_app/features/dashboard/widgets/pending_receipt_list_item.dart';
import 'package:reseebo_app/features/dashboard/widgets/receipt_list_item.dart';

import 'fixtures/receipt_ledger_ui_fixture.dart';

LedgerEntry pendingEntry({
  String supplier = 'Unknown supplier',
  int? amount,
  String? confirmedId,
}) => LedgerEntry(
  id: confirmedId ?? 'pending-import',
  status: LedgerEntryStatus.needsReview,
  recordedAt: DateTime(2026, 9, 3),
  supplierDisplay: supplier,
  provisionalTotalCents: amount,
  pendingId: 'pending-import',
  confirmedReceiptId: confirmedId,
);

Future<LedgerUiAdapter> mixedLedger() async {
  final adapter = LedgerUiAdapter();
  final saved = await adapter.seedConfirmed();
  final detail = await adapter.getReceipt(saved.receiptId);
  adapter.recentRows = [detail.receipt];
  adapter.ledgerRows = [
    pendingEntry(amount: 4900),
    LedgerEntry(
      id: saved.receiptId,
      status: LedgerEntryStatus.confirmed,
      recordedAt: detail.receipt.createdAt,
      supplierDisplay: detail.receipt.supplier.displayName,
      provisionalTotalCents: 2400,
      confirmedReceiptId: saved.receiptId,
    ),
  ];
  return adapter;
}

void main() {
  testWidgets(
    'combined ledger distinguishes imports from confirmed purchases',
    (tester) async {
      final adapter = await mixedLedger();
      String? openedPending;
      Receipt? openedConfirmed;
      await tester.pumpWidget(
        ledgerApp(
          DashboardScreen(
            dataAdapter: adapter,
            onPendingReceiptSelected: (id) => openedPending = id,
            onReceiptSelected: (receipt) => openedConfirmed = receipt,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PendingReceiptListItem), findsOneWidget);
      expect(find.byType(ReceiptListItem), findsOneWidget);
      expect(find.text('1 confirmed'), findsOneWidget);
      expect(find.text('1 needs review'), findsOneWidget);
      expect(find.text('Unknown supplier'), findsOneWidget);
      expect(find.textContaining('Provisional'), findsOneWidget);
      expect(find.text('Needs review'), findsOneWidget);
      await tester.tap(find.byType(PendingReceiptListItem));
      expect(openedPending, 'pending-import');
      await tester.tap(find.byType(ReceiptListItem));
      expect(openedConfirmed!.id, adapter.recentRows!.single.id);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('photos-only pending shows unknown total without a zero amount', (
    tester,
  ) async {
    final adapter = LedgerUiAdapter()
      ..recentRows = []
      ..ledgerRows = [pendingEntry()];
    await tester.pumpWidget(ledgerApp(DashboardScreen(dataAdapter: adapter)));
    await tester.pumpAndSettle();
    expect(find.text('Unknown supplier'), findsOneWidget);
    expect(find.text('Total not available'), findsOneWidget);
    expect(find.text('₱0.00'), findsNothing);
    expect(find.text('0 confirmed'), findsOneWidget);
    expect(find.text('1 needs review'), findsOneWidget);
    expect(find.byType(PendingReceiptListItem), findsOneWidget);
  });

  testWidgets(
    'pending correction uses one existing entry and confirmed count',
    (tester) async {
      final adapter = await mixedLedger();
      final receipt = adapter.recentRows!.single;
      adapter.ledgerRows = [
        LedgerEntry(
          id: receipt.id,
          status: LedgerEntryStatus.needsReview,
          recordedAt: receipt.createdAt,
          supplierDisplay: 'Owner corrected supplier',
          provisionalTotalCents: 1300,
          confirmedReceiptId: receipt.id,
          pendingId: 'pending-correction',
        ),
      ];
      String? selected;
      await tester.pumpWidget(
        ledgerApp(
          DashboardScreen(
            dataAdapter: adapter,
            onPendingReceiptSelected: (id) => selected = id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Receipts (1)'), findsOneWidget);
      expect(find.text('1 confirmed'), findsOneWidget);
      expect(find.text('1 needs review'), findsOneWidget);
      expect(find.byType(PendingReceiptListItem), findsOneWidget);
      expect(find.byType(ReceiptListItem), findsNothing);
      await tester.tap(find.byType(PendingReceiptListItem));
      expect(selected, 'pending-correction');
      expect(adapter.recentRows!.single.totalCents, 2400);
      expect(adapter.ledgerRows!.single.recordedAt, receipt.createdAt);
    },
  );

  testWidgets(
    'pending supplier search leaves confirmed cards available on clear',
    (tester) async {
      final adapter = await mixedLedger();
      await tester.pumpWidget(ledgerApp(DashboardScreen(dataAdapter: adapter)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('dashboard-search')),
        'Unknown',
      );
      await tester.pumpAndSettle();
      expect(find.byType(PendingReceiptListItem), findsOneWidget);
      expect(find.byType(ReceiptListItem), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('dashboard-search')),
        '',
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptListItem), findsOneWidget);
    },
  );

  for (final width in [360.0, 412.0]) {
    testWidgets('combined ledger fits ${width}dp at text scale 2', (
      tester,
    ) async {
      ledgerPhone(tester, width);
      final adapter = await mixedLedger();
      adapter.ledgerRows![0] = pendingEntry(
        supplier: 'A long wholesaler name with a separate branch location',
        amount: 123456789,
      );
      await tester.pumpWidget(
        ledgerApp(DashboardScreen(dataAdapter: adapter), scale: 2),
      );
      await tester.pumpAndSettle();
      expect(find.text('Needs review'), findsOneWidget);
      await revealLedgerFinder(tester, find.byType(ReceiptListItem));
      expect(find.byType(ReceiptListItem), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
