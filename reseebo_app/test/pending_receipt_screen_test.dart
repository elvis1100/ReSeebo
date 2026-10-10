import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/features/receipt_scan/screens/review_match_screen.dart';
import 'package:reseebo_app/features/receipt_scan/widgets/receipt_image_viewer.dart';
import 'package:reseebo_app/features/receipts/screens/pending_receipt_screen.dart';
import 'package:reseebo_app/features/receipts/screens/receipt_detail_screen.dart';
import 'package:reseebo_app/features/receipts/state/pending_receipt_controller.dart';
import 'package:reseebo_app/features/receipts/widgets/receipt_images_preview.dart';

import 'fixtures/receipt_ledger_ui_fixture.dart';

void main() {
  test('edit_keeps_owner_value_and_photos', () async {
    final adapter = LedgerUiAdapter();
    final seeded = await adapter.seedPending();
    final controller = PendingReceiptController(adapter);
    addTearDown(controller.dispose);
    await controller.load(seeded.id);
    final edited = controller.draft!.snapshot();
    edited.lines.single.grossAmountCents = 1300;
    edited.lines.single.amountEdited = true;
    edited.notes = 'Owner checked the amount';
    final saved = await controller.save(edited);
    final reopened = await adapter.getPendingReceipt(saved.id);
    expect(saved.id, seeded.id);
    expect(saved.revision, 2);
    expect(reopened.draft.lines.single.grossAmountCents, 1300);
    expect(reopened.draft.lines.single.extractedUnitPriceCents, 1300);
    expect(reopened.draft.lines.single.normalizedDiscountCents, 200);
    expect(reopened.draft.imagePaths, [
      'owned/original-1.png',
      'owned/original-2.png',
    ]);
    expect(
      reopened.draft.ocrPages.first.recognitionImagePath,
      'owned/recognition-1.png',
    );
    expect(reopened.draft.rawText, 'Original raw OCR\nCoffee 2 24.00');
    expect(reopened.draft.lines.single.confirmed, isFalse);
    expect(adapter.ocrReads, 0);
  });

  test('failed save retries the unchanged payload and command', () async {
    final adapter = LedgerUiAdapter();
    final seeded = await adapter.seedPending();
    final controller = PendingReceiptController(adapter);
    addTearDown(controller.dispose);
    await controller.load(seeded.id);
    final edited = controller.draft!.snapshot()..notes = 'Frozen owner note';
    adapter.failPendingOnce = StateError('Interrupted local write');
    await expectLater(controller.save(edited), throwsStateError);
    final saved = await controller.save(edited.snapshot());
    expect(saved.revision, 2);
    expect(adapter.pendingCommands, hasLength(2));
    expect(
      adapter.pendingCommands[0].operationId,
      adapter.pendingCommands[1].operationId,
    );
    expect(adapter.pendingCommands[1].expectedRevision, 1);
    expect(
      (await adapter.getPendingReceipt(seeded.id)).draft.notes,
      'Frozen owner note',
    );
  });

  test('owner edits after a failed save create a fresh command', () async {
    final adapter = LedgerUiAdapter();
    final seeded = await adapter.seedPending();
    final controller = PendingReceiptController(adapter);
    addTearDown(controller.dispose);
    await controller.load(seeded.id);
    adapter.failPendingOnce = StateError('Interrupted local write');
    await expectLater(
      controller.save(controller.draft!.snapshot()..notes = 'First'),
      throwsStateError,
    );
    await controller.save(
      controller.draft!.snapshot()..notes = 'New owner input',
    );
    expect(
      adapter.pendingCommands[1].operationId,
      isNot(adapter.pendingCommands[0].operationId),
    );
    expect(
      (await adapter.getPendingReceipt(seeded.id)).draft.notes,
      'New owner input',
    );
  });

  test('conflict_preserves_unsaved_input', () async {
    final adapter = LedgerUiAdapter();
    final seeded = await adapter.seedPending();
    final controller = PendingReceiptController(adapter);
    addTearDown(controller.dispose);
    await controller.load(seeded.id);
    await adapter.savePendingReceipt(
      ledgerDraft()..notes = 'Other saved note',
      operationId: 'another-editor',
      pendingId: seeded.id,
      expectedRevision: 1,
    );
    final edited = controller.draft!.snapshot()..notes = 'Unsaved owner note';
    await expectLater(
      controller.save(edited),
      throwsA(isA<RevisionConflictException>()),
    );
    expect(controller.draft!.notes, 'Unsaved owner note');
    expect(controller.pending!.revision, 1);
    expect(
      (await adapter.getPendingReceipt(seeded.id)).draft.notes,
      'Other saved note',
    );
    expect(controller.error, isA<RevisionConflictException>());
  });

  test(
    'confirmation retry after consumed pending retains the same command',
    () async {
      final adapter = LedgerUiAdapter();
      final seeded = await adapter.seedPending(
        draft: ledgerDraft(complete: true),
      );
      final controller = PendingReceiptController(adapter);
      addTearDown(controller.dispose);
      await controller.load(seeded.id);
      adapter.loseConfirmResponseOnce = true;
      await expectLater(controller.confirm(), throwsStateError);
      final resolvedId = await adapter.resolveConfirmedReceiptId(seeded.id);
      expect(resolvedId, isNotNull);
      final result = await controller.confirm();
      expect(result.receiptId, resolvedId);
      expect(result.alreadySaved, isTrue);
      expect(adapter.confirmCommands, hasLength(2));
      expect(
        adapter.confirmCommands[1].operationId,
        adapter.confirmCommands[0].operationId,
      );
      expect(adapter.confirmCommands[1].revision, 1);
      expect(adapter.directConfirmedWrites, 0);
    },
  );

  test('invalid confirmation leaves pending evidence available', () async {
    final adapter = LedgerUiAdapter();
    final seeded = await adapter.seedPending(
      draft: ledgerDraft(photosOnly: true),
    );
    final controller = PendingReceiptController(adapter);
    addTearDown(controller.dispose);
    await controller.load(seeded.id);
    await expectLater(
      controller.confirm(),
      throwsA(isA<ValidationException>()),
    );
    expect((await adapter.getPendingReceipt(seeded.id)).draft.lines, isEmpty);
    expect(controller.draft!.imagePaths, hasLength(2));
    expect(controller.error, isNotNull);
  });

  test('a late pending load cannot overwrite a newer route', () async {
    final adapter = LedgerUiAdapter();
    final seeded = await adapter.seedPending();
    final delayed = Completer<PendingReceipt>();
    adapter.pendingReadBarrier = delayed;
    final controller = PendingReceiptController(adapter);
    addTearDown(controller.dispose);
    final oldLoad = controller.load('older-route');
    adapter.pendingReadBarrier = null;
    await controller.load(seeded.id);
    delayed.complete(
      PendingReceipt(
        id: 'older-route',
        revision: 1,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        draft: ledgerDraft()..notes = 'Late old draft',
      ),
    );
    await oldLoad;
    expect(controller.pending!.id, seeded.id);
    expect(controller.draft!.notes, isEmpty);
  });

  test('disposed pending load publishes no notifications', () async {
    final adapter = LedgerUiAdapter();
    final delayed = Completer<PendingReceipt>();
    adapter.pendingReadBarrier = delayed;
    final controller = PendingReceiptController(adapter);
    var notifications = 0;
    controller.addListener(() => notifications++);
    final load = controller.load('late-route');
    controller.dispose();
    final beforeCompletion = notifications;
    delayed.complete(
      PendingReceipt(
        id: 'late-route',
        revision: 1,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        draft: ledgerDraft(),
      ),
    );
    await load;
    expect(notifications, beforeCompletion);
  });

  testWidgets('pending_is_visible_after_reopen', (tester) async {
    final adapter = LedgerUiAdapter();
    final saved = await adapter.seedPending();
    await tester.pumpWidget(
      ledgerApp(PendingReceiptScreen(adapter: adapter, pendingId: saved.id)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unknown supplier'), findsOneWidget);
    expect(find.text('Needs review'), findsWidgets);
    expect(find.textContaining('Provisional'), findsWidgets);
    expect(find.text('Edit receipt'), findsOneWidget);
    expect(find.text('Review and confirm'), findsOneWidget);
    expect(find.byType(ReceiptImagesPreview), findsOneWidget);
    expect(adapter.ocrReads, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('photos-only pending reopens for adding missing fields', (
    tester,
  ) async {
    final adapter = LedgerUiAdapter();
    final saved = await adapter.seedPending(
      draft: ledgerDraft(photosOnly: true),
    );
    await tester.pumpWidget(
      ledgerApp(PendingReceiptScreen(adapter: adapter, pendingId: saved.id)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unknown supplier'), findsOneWidget);
    await tapLedgerText(tester, 'Edit receipt');
    expect(find.byType(ReviewMatchScreen), findsOneWidget);
    await revealLedgerFinder(tester, find.text('No items found yet'));
    expect(find.text('No items found yet'), findsOneWidget);
    await tapLedgerText(tester, 'Add item');
    expect(find.byKey(const ValueKey('description')), findsOneWidget);
    expect(adapter.ocrReads, 0);
  });

  testWidgets('pending review retains the recognition coordinate evidence', (
    tester,
  ) async {
    final adapter = LedgerUiAdapter();
    final saved = await adapter.seedPending();
    await tester.pumpWidget(
      ledgerApp(PendingReceiptScreen(adapter: adapter, pendingId: saved.id)),
    );
    await tester.pumpAndSettle();
    await tapLedgerText(tester, 'Edit receipt');
    final review = tester.widget<ReviewMatchScreen>(
      find.byType(ReviewMatchScreen),
    );
    final page = review.initialDraft.ocrPages.first;
    expect(page.imagePath, 'owned/original-1.png');
    expect(page.recognitionImagePath, 'owned/recognition-1.png');
    expect(page.textLines.single.tokens.single.left, 4);
    expect(page.textLines.single.tokens.single.top, 8);
    await tapLedgerText(tester, 'Receipt photos');
    for (final viewer in tester.widgetList<ReceiptImageViewer>(
      find.byType(ReceiptImageViewer),
    )) {
      if (viewer.tokens.isNotEmpty) {
        expect(
          viewer.imagePath,
          'owned/recognition-1.png',
          reason: 'Recognition coordinates cannot be drawn on the original.',
        );
      }
    }
    expect(adapter.ocrReads, 0);
  });

  testWidgets('pending review saves its edited revision before confirming', (
    tester,
  ) async {
    final adapter = LedgerUiAdapter();
    final saved = await adapter.seedPending(draft: ledgerDraft(complete: true));
    SaveReceiptResult? confirmed;
    await tester.pumpWidget(
      ledgerApp(
        PendingReceiptScreen(
          adapter: adapter,
          pendingId: saved.id,
          onConfirmed: (value) => confirmed = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tapLedgerText(tester, 'Review and confirm');
    await tapLedgerText(tester, 'Continue to save');
    await tapLedgerText(tester, 'Save receipt');
    expect(confirmed, isNotNull);
    expect(adapter.pendingCommands, hasLength(1));
    expect(adapter.pendingCommands.single.pendingId, saved.id);
    expect(adapter.pendingCommands.single.expectedRevision, 1);
    expect(adapter.confirmCommands, hasLength(1));
    expect(adapter.confirmCommands.single.id, saved.id);
    expect(adapter.confirmCommands.single.revision, 2);
    expect(
      adapter.confirmCommands.single.operationId,
      isNot(adapter.pendingCommands.single.operationId),
    );
    expect(adapter.directConfirmedWrites, 0);
    expect(
      await adapter.resolveConfirmedReceiptId(saved.id),
      confirmed!.receiptId,
    );
  });

  testWidgets('confirmed pending route opens the same saved entry', (
    tester,
  ) async {
    final adapter = LedgerUiAdapter();
    final saved = await adapter.seedPending(draft: ledgerDraft(complete: true));
    final result = await adapter.confirmPendingReceipt(
      saved.id,
      expectedRevision: 1,
      operationId: 'confirm-before-late-open',
    );
    await tester.pumpWidget(
      ledgerApp(PendingReceiptScreen(adapter: adapter, pendingId: saved.id)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ReceiptDetailScreen), findsOneWidget);
    expect(
      tester
          .widget<ReceiptDetailScreen>(find.byType(ReceiptDetailScreen))
          .receiptId,
      result.receiptId,
    );
    expect(find.text('Saved purchase'), findsOneWidget);
    expect(adapter.confirmCommands, hasLength(1));
    expect(adapter.directConfirmedWrites, 0);
  });

  testWidgets('every original pending photo remains accessible', (
    tester,
  ) async {
    final adapter = LedgerUiAdapter();
    final saved = await adapter.seedPending();
    await tester.pumpWidget(
      ledgerApp(PendingReceiptScreen(adapter: adapter, pendingId: saved.id)),
    );
    await tester.pumpAndSettle();
    await tapLedgerText(tester, 'Photo 2');
    expect(find.text('Original receipt · Photo 2'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  for (final width in [360.0, 412.0]) {
    testWidgets('pending detail actions fit ${width}dp at text scale 2', (
      tester,
    ) async {
      ledgerPhone(tester, width);
      final adapter = LedgerUiAdapter();
      final saved = await adapter.seedPending();
      await tester.pumpWidget(
        ledgerApp(
          PendingReceiptScreen(adapter: adapter, pendingId: saved.id),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Review and confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Review and confirm').hitTestable(), findsOneWidget);
      expect(find.text('Needs review'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
