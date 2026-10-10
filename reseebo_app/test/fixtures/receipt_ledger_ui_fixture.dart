import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/adapters/i_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/theme/app_theme.dart';

export 'package:reseebo_app/core/adapters/i_reseebo_data_adapter.dart';

const ledgerProduct = Product(
  id: 'ledger-coffee',
  name: 'Coffee',
  brand: 'Brand X',
  variant: 'Original',
  size: '26g',
);

ReceiptDraft ledgerDraft({bool complete = false, bool photosOnly = false}) =>
    ReceiptDraft(
      operationId: 'original-import-command',
      imagePath: 'owned/original-1.png',
      imagePaths: const ['owned/original-1.png', 'owned/original-2.png'],
      recognitionImagePath: 'owned/recognition-1.png',
      supplierName: complete ? 'Saved wholesaler' : '',
      purchasedAt: DateTime(2026, 9, 3),
      dateConfirmed: complete,
      rawText: 'Original raw OCR\nCoffee 2 24.00',
      detectedTotalCents: photosOnly ? null : 2400,
      provenance: {
        ReceiptMetadataField.purchasedAt: ReceiptFieldProvenance(
          origin: complete
              ? ReceiptFieldOrigin.ownerEdited
              : ReceiptFieldOrigin.assumed,
          explanation: 'Import date proposed on 3 September.',
        ),
      },
      ocrPages: [
        ReceiptOcrPage(
          imagePath: 'owned/original-1.png',
          recognitionImagePath: 'owned/recognition-1.png',
          textLines: const [
            OcrTextLine(
              text: 'Coffee 2 24.00',
              left: 4,
              top: 8,
              width: 100,
              height: 20,
              tokens: [
                OcrTextToken(
                  text: 'Coffee',
                  left: 4,
                  top: 8,
                  width: 40,
                  height: 20,
                ),
              ],
            ),
          ],
        ),
        const ReceiptOcrPage(imagePath: 'owned/original-2.png', textLines: []),
      ],
      lines: photosOnly
          ? []
          : [
              ParsedLineItem(
                id: 'draft-coffee',
                description: 'Brand X Original Coffee 26g',
                productId: ledgerProduct.id,
                quantity: 2,
                unit: PurchaseUnit.piece,
                piecesPerPack: 1,
                grossAmountCents: 2400,
                confirmed: complete,
                extractedUnitPriceCents: 1300,
                normalizedDiscountCents: 200,
                provenance: const {
                  ReceiptSuggestionField.amount: ReceiptFieldProvenance(
                    origin: ReceiptFieldOrigin.ownerEdited,
                    explanation: 'Owner entered final amount paid.',
                  ),
                },
              ),
            ],
    );

class PendingCommand {
  PendingCommand(
    this.draft,
    this.operationId,
    this.pendingId,
    this.expectedRevision,
    this.correctionOfReceiptId,
    this.expectedConfirmedRevision,
  );
  final ReceiptDraft draft;
  final String operationId;
  final String? pendingId;
  final int? expectedRevision;
  final String? correctionOfReceiptId;
  final int? expectedConfirmedRevision;
}

class ConfirmCommand {
  ConfirmCommand(this.id, this.revision, this.operationId);
  final String id;
  final int revision;
  final String operationId;
}

/// Uses the adapter's real in-memory persistence. Only fault injection and
/// controlled delayed reads replace behavior, so UI assertions inspect data.
class LedgerUiAdapter extends MockReseeboDataAdapter {
  LedgerUiAdapter() {
    // Mock saves execute synchronously before returning their completed Future.
    // Seed the catalog in fixture setup, rather than mutating it during reads.
    unawaited(super.saveProduct(ledgerProduct));
  }
  final pendingCommands = <PendingCommand>[];
  final confirmCommands = <ConfirmCommand>[];
  List<LedgerEntry>? ledgerRows;
  List<Receipt>? recentRows;
  Completer<PendingReceipt>? pendingReadBarrier;
  Object? failPendingOnce;
  bool loseConfirmResponseOnce = false;
  int directConfirmedWrites = 0;
  int ocrReads = 0;
  int comparisonReads = 0;

  @override
  Future<ProductComparisonData> getProductComparison(String id) async {
    comparisonReads++;
    return super.getProductComparison(id);
  }

  @override
  Future<PendingReceipt> getPendingReceipt(String id) =>
      pendingReadBarrier?.future ?? super.getPendingReceipt(id);

  @override
  Future<List<LedgerEntry>> getLedgerEntries({
    int limit = 200,
    String? query,
  }) => ledgerRows == null
      ? super.getLedgerEntries(limit: limit, query: query)
      : Future.value(
          ledgerRows!
              .where(
                (entry) =>
                    query == null ||
                    entry.supplierDisplay.toLowerCase().contains(
                      query.toLowerCase(),
                    ),
              )
              .toList(),
        );

  @override
  Future<List<Receipt>> getRecentReceipts({int limit = 200, String? query}) =>
      recentRows == null
      ? super.getRecentReceipts(limit: limit, query: query)
      : Future.value(List.of(recentRows!));

  @override
  Future<List<Product>> getProducts({String? query}) async => [ledgerProduct];

  @override
  Future<PendingSaveResult> savePendingReceipt(
    ReceiptDraft draft, {
    required String operationId,
    String? pendingId,
    int? expectedRevision,
    String? correctionOfReceiptId,
    int? expectedConfirmedRevision,
  }) async {
    pendingCommands.add(
      PendingCommand(
        draft.snapshot(),
        operationId,
        pendingId,
        expectedRevision,
        correctionOfReceiptId,
        expectedConfirmedRevision,
      ),
    );
    final failure = failPendingOnce;
    failPendingOnce = null;
    if (failure != null) throw failure;
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
  }) async {
    confirmCommands.add(ConfirmCommand(id, expectedRevision, operationId));
    final result = await super.confirmPendingReceipt(
      id,
      expectedRevision: expectedRevision,
      operationId: operationId,
    );
    if (loseConfirmResponseOnce) {
      loseConfirmResponseOnce = false;
      throw StateError('The local confirmation response was interrupted.');
    }
    return result;
  }

  @override
  Future<SaveReceiptResult> saveConfirmedReceipt(ReceiptDraft draft) async {
    directConfirmedWrites++;
    return super.saveConfirmedReceipt(draft);
  }

  @override
  Future<ReceiptDraft> processReceiptImage(
    String localImagePath, {
    String? recognitionImagePath,
    String? comparisonImagePath,
    OcrEngineId engineId = OcrEngineId.mlKit,
  }) async {
    ocrReads++;
    throw StateError('Reopening saved evidence must never run OCR.');
  }

  Future<PendingSaveResult> seedPending({ReceiptDraft? draft}) async {
    await super.saveProduct(ledgerProduct);
    return super.savePendingReceipt(
      draft ?? ledgerDraft(),
      operationId: 'seed-pending',
    );
  }

  Future<SaveReceiptResult> seedConfirmed() async {
    await super.saveProduct(ledgerProduct);
    return super.saveConfirmedReceipt(ledgerDraft(complete: true));
  }
}

Widget ledgerApp(Widget child, {double scale = 1}) => MaterialApp(
  theme: AppTheme.lightTheme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);

void ledgerPhone(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> tapLedgerText(WidgetTester tester, String text) async {
  final target = find.text(text).first;
  await revealLedgerFinder(tester, target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> revealLedgerFinder(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 30 && target.evaluate().isEmpty; attempt++) {
    final dashboard = find.byKey(
      const PageStorageKey('dashboard-receipts-list'),
    );
    final scroll = dashboard.evaluate().isNotEmpty
        ? dashboard
        : find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .first;
    await tester.drag(scroll, const Offset(0, -240));
    await tester.pumpAndSettle();
  }
  expect(
    target,
    findsWidgets,
    reason: 'The reachable control must build while scrolling.',
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}
