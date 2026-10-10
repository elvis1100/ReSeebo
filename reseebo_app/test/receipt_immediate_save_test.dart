import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/models/ocr_engine.dart';
import 'package:reseebo_app/core/models/pending_receipt.dart';
import 'package:reseebo_app/features/receipt_scan/screens/capture_screen.dart';
import 'package:reseebo_app/features/receipt_scan/screens/review_match_screen.dart';
import 'package:reseebo_app/features/receipt_scan/widgets/duplicate_review_dialog.dart';
import 'package:reseebo_app/features/receipt_scan/state/receipt_review_state.dart';

import 'fixtures/receipt_scan_widget_fixture.dart';

const _coffee = Product(
  id: 'coffee-26',
  name: 'Coffee',
  brand: 'Brand X',
  variant: 'Original',
  size: '26g',
);

class _PendingDuplicateAdapter extends ScanWidgetAdapter {
  @override
  Future<PendingReceipt> getPendingReceipt(String id) async => PendingReceipt(
    id: id,
    revision: 1,
    createdAt: DateTime(2026, 10, 9),
    updatedAt: DateTime(2026, 10, 9),
    draft: ReceiptDraft(
      imagePath: 'earlier.png',
      supplierName: 'Earlier Corner Shop',
      detectedTotalCents: 4200,
    ),
  );
}

class _HistoryScanAdapter extends ScanWidgetAdapter {
  final historyQueries = <String>[];

  @override
  Future<List<Product>> getProducts({String? query}) async => const [
    _coffee,
    Product(
      id: 'coffee-50',
      name: 'Coffee',
      brand: 'Brand X',
      variant: 'Original',
      size: '50g',
    ),
  ];
  @override
  Future<List<Supplier>> getSuppliers() async => const [
    Supplier(id: 'shop', name: 'Corner Shop'),
  ];
  @override
  Future<List<ProductMatchSuggestion>> matchAliases(
    String description, {
    String? supplierId,
  }) async => [
    ProductMatchSuggestion(
      product: _coffee,
      reason: 'Confirmed supplier alias',
      exactAlias: true,
    ),
  ];

  @override
  Future<ProductComparisonData> getProductComparison(String productId) async {
    historyQueries.add(productId);
    return ProductComparisonData(
      product: _coffee,
      profile: const StoreProfile(),
      latestPrices: const [],
      history: [
        PriceHistoryRecord(
          purchase: PurchaseRecord(
            id: 'prior-price',
            receiptId: 'prior-receipt',
            productId: _coffee.id,
            supplier: const Supplier(id: 'shop', name: 'Corner Shop'),
            purchasedAt: DateTime(2026, 10, 8),
            hasPurchaseTime: false,
            recordedAt: DateTime(2026, 10, 8),
            originalDescription: 'Brand X Coffee Original 26g',
            quantity: 1,
            unit: PurchaseUnit.piece,
            piecesPerPack: 1,
            netAmountCents: 2100,
            imagePath: 'prior.png',
          ),
        ),
      ],
    );
  }

  @override
  Future<ReceiptDraft> processReceiptImages(
    List<String> localImagePaths, {
    List<String>? recognitionImagePaths,
    List<String>? comparisonImagePaths,
    OcrEngineId engineId = OcrEngineId.mlKit,
    String preprocessingRevision = '1',
  }) async {
    reads.add(engineId);
    return ReceiptDraft(
      imagePath: localImagePaths.first,
      imagePaths: localImagePaths,
      supplierName: 'Corner Shop',
      lines: [ParsedLineItem(description: 'X CFE 26G', quantity: 2)],
    );
  }
}

void main() {
  test(
    'returning unchanged review preserves command while owner edit starts a new update',
    () async {
      final adapter = ScanWidgetAdapter();
      final review = ReceiptReviewState(
        adapter: adapter,
        importedAt: DateTime(2024, 1, 2),
        draft: ReceiptDraft(
          imagePaths: [],
          lines: [ParsedLineItem(description: 'Coffee')],
        ),
      );
      addTearDown(review.dispose);
      await review.load();
      await review.savePending();
      final resumed = review.resumeSnapshot(review.draft.snapshot());
      addTearDown(resumed.dispose);
      await resumed.savePending();
      expect(adapter.pendingCommands.last, adapter.pendingCommands.first);
      expect(adapter.pendingTargets, [null, null]);
      resumed.editText(
        resumed.draft.lines.single,
        ReceiptLineField.quantity,
        '2',
      );
      await resumed.savePending();
      expect(
        adapter.pendingCommands.last,
        isNot(adapter.pendingCommands.first),
      );
      expect(adapter.pendingTargets.last, 'pending-saved');
      expect(adapter.pendingRevisions.last, 1);
      expect(adapter.pendingDrafts.last.purchasedAt, DateTime(2024, 1, 2));
    },
  );

  testWidgets(
    'photos-only retry refuses changed bytes until owner starts a fresh command',
    (tester) async {
      final adapter = ScanWidgetAdapter()..failSavingOnce = true;
      final state = await fixtureCapture(tester, adapter);
      await tester.pumpWidget(
        scanApp(CaptureScreen(dataAdapter: adapter, captureState: state)),
      );
      await tester.pumpAndSettle();
      await tapCaptureAction(tester, find.text('Save photos for later'));
      final original = File(state.pages.single.originalPath);
      await tester.runAsync(() async {
        final bytes = await original.readAsBytes();
        await original.writeAsBytes([...bytes, 0]);
      });
      await tapCaptureAction(tester, find.text('Save photos for later'));
      expect(find.text('Receipt photos changed'), findsOneWidget);
      expect(adapter.pendingCommands, hasLength(1));
      await tapCaptureAction(tester, find.text('Keep reviewing'));
      await tapCaptureAction(tester, find.text('Save photos for later'));
      await tapCaptureAction(tester, find.text('Use current photos'));
      expect(adapter.pendingCommands, hasLength(2));
      expect(
        adapter.pendingCommands.last,
        isNot(adapter.pendingCommands.first),
      );
      expect(adapter.pendingDrafts.last.purchasedAt, isNull);
      expect(adapter.pendingDrafts.last.lines, isEmpty);
      expect(adapter.reads, isEmpty);
    },
  );
  testWidgets(
    'pending screen uses its original import date only after an owner edit',
    (tester) async {
      final adapter = ScanWidgetAdapter();
      await tester.pumpWidget(
        scanApp(
          ReviewMatchScreen(
            dataAdapter: adapter,
            initialDraft: ReceiptDraft(
              imagePath: 'original.png',
              lines: [ParsedLineItem(description: 'Coffee')],
            ),
            pendingId: 'pending',
            expectedRevision: 1,
            importedAt: DateTime(2024, 1, 2),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapCaptureAction(tester, find.text('Save Needs review'));
      expect(adapter.pendingDrafts.single.purchasedAt, isNull);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('quantity')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byKey(const ValueKey('quantity')), '2');
      await tester.pump();
      await tapCaptureAction(tester, find.text('Save Needs review'));
      expect(adapter.pendingDrafts.last.purchasedAt, DateTime(2024, 1, 2));
      expect(
        adapter.pendingCommands.last,
        isNot(adapter.pendingCommands.first),
      );
      expect(adapter.pendingRevisions, [1, 2]);
    },
  );

  test(
    'reopening pending keeps saved history proposal and import date until owner edits',
    () async {
      final adapter = _HistoryScanAdapter();
      final stored = ReceiptDraft(
        imagePath: 'stored.png',
        supplierId: 'shop',
        supplierName: 'Corner Shop',
        purchasedAt: DateTime(2024, 1, 2),
        detectedTotalCents: 3000,
        provenance: {
          ReceiptMetadataField.purchasedAt: const ReceiptFieldProvenance(
            origin: ReceiptFieldOrigin.assumed,
            explanation: 'Import date assumed; confirm the purchase date.',
          ),
          ReceiptMetadataField.total: const ReceiptFieldProvenance(
            origin: ReceiptFieldOrigin.calculated,
            explanation: 'Sum of saved proposals.',
          ),
        },
        lines: [
          ParsedLineItem(
            description: 'X CFE 26G',
            productId: 'coffee-26',
            quantity: 2,
            unit: PurchaseUnit.piece,
            piecesPerPack: 1,
            grossAmountCents: 3000,
            provenance: {
              ReceiptSuggestionField.amount: ReceiptFieldProvenance(
                origin: ReceiptFieldOrigin.history,
                explanation: 'Saved historical proposal',
                sourceSupplierName: 'Old Corner Shop',
                sourcePurchasedAt: DateTime(2023, 12, 1),
              ),
            },
          ),
        ],
      );
      final review = ReceiptReviewState(
        adapter: adapter,
        draft: stored,
        pendingId: 'saved-pending',
        expectedRevision: 1,
      );
      addTearDown(review.dispose);
      await review.load();
      expect(review.draft.purchasedAt, DateTime(2024, 1, 2));
      expect(review.draft.lines.single.grossAmountCents, 3000);
      expect(review.draft.detectedTotalCents, 3000);
      expect(
        review
            .draft
            .lines
            .single
            .provenance[ReceiptSuggestionField.amount]
            ?.sourceSupplierName,
        'Old Corner Shop',
      );
      expect(
        review.draft.provenance[ReceiptMetadataField.purchasedAt]?.origin,
        ReceiptFieldOrigin.assumed,
      );
      review.editText(
        review.draft.lines.single,
        ReceiptLineField.quantity,
        '3',
      );
      expect(review.draft.lines.single.grossAmountCents, 6300);
      expect(review.draft.purchasedAt, DateTime(2024, 1, 2));
      expect(stored.lines.single.grossAmountCents, 3000);
    },
  );

  testWidgets(
    'pending-context confirmed Save never uses the initial purchase writer',
    (tester) async {
      final adapter = ScanWidgetAdapter();
      final draft = ReceiptDraft(
        imagePath: 'original.png',
        supplierName: 'Corner Shop',
        purchasedAt: DateTime(2026, 10, 8),
        dateConfirmed: true,
        lines: [
          ParsedLineItem(
            description: 'Coffee',
            quantity: 2,
            unit: PurchaseUnit.piece,
            piecesPerPack: 1,
            grossAmountCents: 4200,
            confirmed: true,
          ),
        ],
      );
      await tester.pumpWidget(
        scanApp(
          ReviewMatchScreen(
            dataAdapter: adapter,
            initialDraft: draft,
            pendingId: 'existing-pending',
            expectedRevision: 3,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue to save'));
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save receipt'),
      );
      expect(button.onPressed, isNull);
      expect(
        find.textContaining('confirm from the saved receipt'),
        findsOneWidget,
      );
      expect(adapter.confirmedWrites, 0);
    },
  );

  testWidgets(
    'duplicate dialog displays pending candidate as provisional Needs review',
    (tester) async {
      final openedPending = <String>[];
      await tester.pumpWidget(
        scanApp(
          Scaffold(
            body: DuplicateReviewDialog(
              adapter: _PendingDuplicateAdapter(),
              receiptIds: const ['pending-earlier'],
              onOpenPendingReceipt: openedPending.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Earlier Corner Shop'), findsOneWidget);
      expect(find.textContaining('Needs review'), findsOneWidget);
      expect(find.textContaining('Provisional total: ₱42.00'), findsOneWidget);
      expect(find.textContaining('Purchase date unresolved'), findsOneWidget);
      await tester.tap(find.text('Earlier Corner Shop'));
      await tester.pumpAndSettle();
      expect(openedPending, ['pending-earlier']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('completed unchanged save repeats its original insert context', (
    tester,
  ) async {
    final adapter = ScanWidgetAdapter();
    final state = await fixtureCapture(tester, adapter);
    await tester.pumpWidget(
      scanApp(CaptureScreen(dataAdapter: adapter, captureState: state)),
    );
    await tester.pumpAndSettle();
    await finishRead(tester);
    await tapCaptureAction(tester, find.text('Save Needs review'));
    await tapCaptureAction(tester, find.text('Save Needs review'));
    expect(adapter.pendingCommands.last, adapter.pendingCommands.first);
    expect(adapter.pendingTargets, [null, null]);
    expect(adapter.pendingRevisions, [null, null]);
  });

  testWidgets('Review Back returns a private editable snapshot to capture', (
    tester,
  ) async {
    final adapter = ScanWidgetAdapter();
    final initial = ReceiptDraft(
      imagePath: 'original.png',
      lines: [ParsedLineItem(description: 'Coffee')],
    );
    ReceiptDraft? returned;
    await tester.pumpWidget(
      scanApp(
        ReviewMatchScreen(
          dataAdapter: adapter,
          initialDraft: initial,
          onBack: () {},
          onDraftChanged: (draft) => returned = draft,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('description')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('description')),
      'Owner edited coffee',
    );
    await tester.pump();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(returned!.lines.single.description, 'Owner edited coffee');
    expect(
      returned!
          .lines
          .single
          .provenance[ReceiptSuggestionField.description]
          ?.origin,
      ReceiptFieldOrigin.ownerEdited,
    );
    expect(initial.lines.single.description, 'Coffee');
  });

  testWidgets(
    'direct save resolves unique supplier alias then confirmed history and shows human estimates',
    (tester) async {
      final adapter = _HistoryScanAdapter();
      final state = await fixtureCapture(tester, adapter);
      await tester.pumpWidget(
        scanApp(CaptureScreen(dataAdapter: adapter, captureState: state)),
      );
      await tester.pumpAndSettle();
      await finishRead(tester);
      await revealCaptureBody(
        tester,
        find.textContaining('Provisional cost per piece'),
      );
      expect(find.textContaining('₱21.00'), findsWidgets);
      expect(find.textContaining('Corner Shop'), findsWidgets);
      await tapCaptureAction(tester, find.text('Save Needs review'));
      final saved = adapter.pendingDrafts.single;
      expect(saved.supplierId, 'shop');
      expect(saved.lines.single.productId, 'coffee-26');
      expect(saved.lines.single.grossAmountCents, 4200);
      expect(
        saved.lines.single.provenance[ReceiptSuggestionField.amount]?.origin,
        ReceiptFieldOrigin.history,
      );
      expect(saved.lines.single.confirmed, isFalse);
      expect(adapter.historyQueries, ['coffee-26']);
      expect(state.selectedDraftSnapshot().lines.single.productId, isNull);
      expect(
        state.selectedDraftSnapshot().lines.single.grossAmountCents,
        isNull,
      );
    },
  );

  testWidgets(
    'immediate OCR save applies review suggestions without confirming or mutating cache',
    (tester) async {
      final adapter = ScanWidgetAdapter();
      final state = await fixtureCapture(tester, adapter);
      await tester.pumpWidget(
        scanApp(CaptureScreen(dataAdapter: adapter, captureState: state)),
      );
      await tester.pumpAndSettle();
      await finishRead(tester);
      await tapCaptureAction(tester, find.text('Save Needs review'));
      final saved = adapter.pendingDrafts.single;
      expect(saved.dateConfirmed, isFalse);
      expect(saved.lines.single.confirmed, isFalse);
      expect(saved.detectedTotalCents, 4200);
      expect(
        saved.provenance[ReceiptMetadataField.total]?.origin,
        ReceiptFieldOrigin.calculated,
      );
      expect(state.selectedDraftSnapshot().detectedTotalCents, isNull);
      expect(adapter.reads, hasLength(1));
    },
  );

  for (final failed in [true, false]) {
    testWidgets(
      '${failed ? 'failed OCR' : 'no recognized lines'} still saves photos without fabricated lines',
      (tester) async {
        final adapter = ScanWidgetAdapter()
          ..failReading = failed
          ..noLines = !failed;
        final state = await fixtureCapture(tester, adapter);
        await tester.pumpWidget(
          scanApp(CaptureScreen(dataAdapter: adapter, captureState: state)),
        );
        await tester.pumpAndSettle();
        await finishRead(tester);
        await tapCaptureAction(tester, find.text('Save photos for later'));
        final saved = adapter.pendingDrafts.single;
        expect(saved.imagePaths, [state.pages.single.originalPath]);
        expect(saved.lines, isEmpty);
        expect(saved.textLines, isEmpty);
        expect(saved.purchasedAt, isNull);
        expect(saved.detectedTotalCents, isNull);
        expect(adapter.reads, hasLength(1));
      },
    );
  }

  testWidgets('zero photos cannot save a pending receipt', (tester) async {
    final adapter = ScanWidgetAdapter();
    await tester.pumpWidget(scanApp(CaptureScreen(dataAdapter: adapter)));
    await tester.pumpAndSettle();
    expect(find.text('Save photos for later'), findsNothing);
    expect(find.text('Save Needs review'), findsNothing);
    expect(adapter.pendingCommands, isEmpty);
  });

  testWidgets(
    'double tap writes once and retry reuses frozen payload and command',
    (tester) async {
      final adapter = ScanWidgetAdapter()
        ..saveBarrier = Completer<void>()
        ..failSavingOnce = true;
      final state = await fixtureCapture(tester, adapter);
      await tester.pumpWidget(
        scanApp(CaptureScreen(dataAdapter: adapter, captureState: state)),
      );
      await tester.pumpAndSettle();
      await finishRead(tester);
      await tester.tap(find.text('Save Needs review'));
      await tester.tap(find.text('Save Needs review'));
      await tester.pump();
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Save Needs review'),
            )
            .onPressed,
        isNull,
      );
      for (var i = 0; i < 500 && adapter.pendingCommands.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(adapter.pendingCommands, hasLength(1));
      adapter.saveBarrier!.complete();
      await settleCaptureAction(tester);
      final firstDate = adapter.pendingDrafts.first.purchasedAt;
      await tapCaptureAction(tester, find.text('Save Needs review'));
      expect(adapter.pendingCommands, hasLength(2));
      expect(adapter.pendingCommands.last, adapter.pendingCommands.first);
      expect(adapter.pendingDrafts.last.purchasedAt, firstDate);
      expect(
        adapter.pendingDrafts.last.operationId,
        adapter.pendingDrafts.first.operationId,
      );
    },
  );

  testWidgets(
    'Review saves an unresolved draft separately from confirmed Save',
    (tester) async {
      final adapter = ScanWidgetAdapter();
      await tester.pumpWidget(
        scanApp(
          ReviewMatchScreen(
            dataAdapter: adapter,
            initialDraft: ReceiptDraft(
              imagePath: 'original.png',
              lines: [ParsedLineItem(description: 'Unresolved coffee')],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapCaptureAction(tester, find.text('Save Needs review'));
      expect(
        adapter.pendingDrafts.single.lines.single.grossAmountCents,
        isNull,
      );
      expect(adapter.pendingDrafts.single.lines.single.confirmed, isFalse);
      expect(find.text('Continue to save'), findsOneWidget);
    },
  );
}
