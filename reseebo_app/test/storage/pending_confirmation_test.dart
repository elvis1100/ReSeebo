import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/i_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';

import 'receipt_confirmation_fixture.dart';

/// Pauses after the real adapter captured a pending revision. This controls the
/// storage read boundary without replacing persistence or revision behavior.
class _PausedPendingReadMock extends MockReseeboDataAdapter {
  bool pauseNextRead = false;
  final captured = Completer<void>();
  final resume = Completer<void>();

  @override
  Future<PendingReceipt> getPendingReceipt(String id) async {
    final pending = await super.getPendingReceipt(id);
    if (pauseNextRead) {
      pauseNextRead = false;
      captured.complete();
      await resume.future;
    }
    return pending;
  }
}

void main() {
  late ReceiptConfirmationFixture f;
  setUp(() async {
    f = ReceiptConfirmationFixture();
    await f.setUp();
  });
  tearDown(() => f.tearDown());

  test(
    'mock queued confirmation cannot discard a successful concurrent pending edit',
    () async {
      final adapter = _PausedPendingReadMock();
      final saved = await adapter.savePendingReceipt(
        await f.draft(),
        operationId: 'save',
      );
      final edited = (await adapter.getPendingReceipt(saved.id)).draft;
      edited.notes = 'new successful owner edit';
      edited.lines.single.grossAmountCents = 130000;
      adapter.pauseNextRead = true;
      final confirmation = adapter.confirmPendingReceipt(
        saved.id,
        expectedRevision: 1,
        operationId: 'confirm',
      );
      await adapter.captured.future;
      final editOutcome = adapter
          .savePendingReceipt(
            edited,
            operationId: 'edit',
            pendingId: saved.id,
            expectedRevision: 1,
          )
          .then<Object>(
            (result) => result,
            onError: (Object error, StackTrace stack) => error,
          );
      adapter.resume.complete();
      final result = await confirmation;
      // Confirmation was submitted first. The queued edit must receive a typed
      // conflict instead of reporting success for data that confirmation removed.
      expect(await editOutcome, isA<RevisionConflictException>());
      expect(
        (await adapter.getConfirmedReceiptEdit(result.receiptId)).draft.notes,
        '',
      );
      expect(
        (await adapter.getConfirmedReceiptEdit(
          result.receiptId,
        )).draft.lines.single.grossAmountCents,
        100000,
      );
    },
  );

  test(
    'mock queued pending save captures its private payload at invocation',
    () async {
      final adapter = _PausedPendingReadMock();
      final first = await adapter.savePendingReceipt(
        await f.draft(),
        operationId: 'save',
      );
      adapter.pauseNextRead = true;
      final confirming = adapter.confirmPendingReceipt(
        first.id,
        expectedRevision: 1,
        operationId: 'confirm',
      );
      await adapter.captured.future;
      final draft = await f.draft(amount: 130000);
      draft.notes = 'submitted notes';
      final saving = adapter.savePendingReceipt(
        draft,
        operationId: 'other-save',
      );
      draft.notes = 'later caller mutation';
      draft.lines.single.grossAmountCents = 1;
      adapter.resume.complete();
      await confirming;
      final saved = await saving;
      final persisted = (await adapter.getPendingReceipt(saved.id)).draft;
      expect(persisted.notes, 'submitted notes');
      expect(persisted.lines.single.grossAmountCents, 130000);
    },
  );

  test(
    'mock queued direct save cannot claim an in-flight confirmation command ID',
    () async {
      final adapter = _PausedPendingReadMock();
      final first = await adapter.savePendingReceipt(
        await f.draft(),
        operationId: 'save',
      );
      final other = await f.draft();
      final direct = ReceiptDraft(
        operationId: 'confirm',
        imagePath: other.imagePath,
        supplierName: other.supplierName,
        purchasedAt: other.purchasedAt,
        dateConfirmed: true,
        lines: other.lines,
      );
      adapter.pauseNextRead = true;
      final confirming = adapter.confirmPendingReceipt(
        first.id,
        expectedRevision: 1,
        operationId: 'confirm',
      );
      await adapter.captured.future;
      final directOutcome = adapter
          .saveConfirmedReceipt(direct)
          .then<Object>(
            (result) => result,
            onError: (Object error, StackTrace stack) => error,
          );
      adapter.resume.complete();
      await confirming;
      expect(await directOutcome, isA<ValidationException>());
      expect((await adapter.getLedgerEntries(query: 'Supplier A')).length, 1);
    },
  );

  test(
    'confirmation_is_atomic_and_retryable after pending deletion and restart',
    () async {
      final draft = await f.draft();
      final saved = await f.adapter.savePendingReceipt(
        draft,
        operationId: 'save',
      );
      final pending = await f.adapter.getPendingReceipt(saved.id);
      final result = await f.adapter.confirmPendingReceipt(
        saved.id,
        expectedRevision: 1,
        operationId: 'confirm',
      );
      expect(await f.count('receipts'), 1);
      expect(await f.count('purchase_lines'), 1);
      expect(await f.count('pending_receipts'), 0);
      expect(result.unitCostsCents, [10000]);
      expect(
        (await f.adapter.getReceipt(result.receiptId)).receipt.imagePaths,
        pending.draft.imagePaths,
      );
      await File(draft.imagePath).delete();
      await f.adapter.close();
      await f.reopen();
      final retry = await f.adapter.confirmPendingReceipt(
        saved.id,
        expectedRevision: 1,
        operationId: 'confirm',
      );
      expect(retry.receiptId, result.receiptId);
      expect(retry.lineIds, result.lineIds);
      expect(retry.unitCostsCents, [10000]);
      expect(retry.alreadySaved, isTrue);
      expect(await f.count('receipts'), 1);
    },
  );

  test(
    'failure after receipt insert rolls back lines aliases and pending deletion',
    () async {
      final saved = await f.adapter.savePendingReceipt(
        await f.draft(),
        operationId: 'save',
      );
      final pending = await f.adapter.getPendingReceipt(saved.id);
      await f.db.execute(
        "CREATE TRIGGER fail_line BEFORE INSERT ON purchase_lines BEGIN SELECT RAISE(ABORT, 'injected after receipt'); END",
      );
      await expectLater(
        f.adapter.confirmPendingReceipt(
          saved.id,
          expectedRevision: 1,
          operationId: 'confirm',
        ),
        throwsA(isA<Exception>()),
      );
      for (final table in [
        'receipts',
        'purchase_lines',
        'suppliers',
        'products',
        'supplier_product_aliases',
        'receipt_evidence',
      ]) {
        expect(await f.count(table), 0, reason: table);
      }
      expect((await f.adapter.getPendingReceipt(saved.id)).revision, 1);
      expect(await File(pending.draft.imagePath).exists(), isTrue);
      await f.db.execute('DROP TRIGGER fail_line');
      expect(
        (await f.adapter.confirmPendingReceipt(
          saved.id,
          expectedRevision: 1,
          operationId: 'confirm',
        )).receiptId,
        isNotEmpty,
      );
    },
  );

  test('invalid_pending_stays_pending', () async {
    final draft = await f.draft();
    draft.lines.single.grossAmountCents = null;
    final saved = await f.adapter.savePendingReceipt(
      draft,
      operationId: 'save',
    );
    await expectLater(
      f.adapter.confirmPendingReceipt(
        saved.id,
        expectedRevision: 1,
        operationId: 'confirm',
      ),
      throwsA(isA<ValidationException>()),
    );
    expect(await f.count('receipts'), 0);
    expect(
      (await f.adapter.getPendingReceipt(
        saved.id,
      )).draft.lines.single.grossAmountCents,
      isNull,
    );
  });

  test(
    'confirmed_entry_link_survives and two confirmation commands produce one receipt',
    () async {
      final saved = await f.adapter.savePendingReceipt(
        await f.draft(),
        operationId: 'save',
      );
      final first = await f.adapter.confirmPendingReceipt(
        saved.id,
        expectedRevision: 1,
        operationId: 'first',
      );
      final second = await f.adapter.confirmPendingReceipt(
        saved.id,
        expectedRevision: 1,
        operationId: 'second',
      );
      expect(second.receiptId, first.receiptId);
      expect(second.alreadySaved, isTrue);
      expect(
        (await f.db.query('ledger_entry_links')).single['confirmed_receipt_id'],
        first.receiptId,
      );
      expect(
        await f.adapter.resolveConfirmedReceiptId(saved.id),
        first.receiptId,
      );
      expect(
        (await f.adapter.getLedgerEntries()).single.confirmedReceiptId,
        first.receiptId,
      );
      expect(
        (await f.adapter.getLedgerEntries()).single.status,
        LedgerEntryStatus.confirmed,
      );
      expect(await f.count('receipts'), 1);
    },
  );

  test(
    'used confirmation operation rejects changed revision and target',
    () async {
      final a = await f.adapter.savePendingReceipt(
        await f.draft(),
        operationId: 'save-a',
      );
      await f.adapter.confirmPendingReceipt(
        a.id,
        expectedRevision: 1,
        operationId: 'confirm',
      );
      final b = await f.adapter.savePendingReceipt(
        await f.draft(),
        operationId: 'save-b',
      );
      await expectLater(
        f.adapter.confirmPendingReceipt(
          a.id,
          expectedRevision: 2,
          operationId: 'confirm',
        ),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        f.adapter.confirmPendingReceipt(
          b.id,
          expectedRevision: 1,
          operationId: 'confirm',
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(await f.count('receipts'), 1);
    },
  );

  test('stale_pending_revision rejects before committing purchase', () async {
    final a = await f.adapter.savePendingReceipt(
      await f.draft(),
      operationId: 'save',
    );
    final draft = (await f.adapter.getPendingReceipt(a.id)).draft;
    draft.notes = 'changed';
    await f.adapter.savePendingReceipt(
      draft,
      operationId: 'edit',
      pendingId: a.id,
      expectedRevision: 1,
    );
    await expectLater(
      f.adapter.confirmPendingReceipt(
        a.id,
        expectedRevision: 1,
        operationId: 'confirm',
      ),
      throwsA(isA<RevisionConflictException>()),
    );
    expect(await f.count('receipts'), 0);
    expect((await f.adapter.getPendingReceipt(a.id)).revision, 2);
  });

  test(
    'first confirmation maps temporary IDs to saved IDs in private evidence',
    () async {
      final a = await f.adapter.savePendingReceipt(
        await f.draft(),
        operationId: 'save',
      );
      final result = await f.adapter.confirmPendingReceipt(
        a.id,
        expectedRevision: 1,
        operationId: 'confirm',
      );
      final edit = await f.adapter.getConfirmedReceiptEdit(result.receiptId);
      expect(edit.revision, 1);
      expect(edit.draft.lines.single.id, result.lineIds.single);
      expect(edit.draft.lines.single.productId, isNotNull);
      edit.draft.lines.single.description = 'leaked edit';
      expect(
        (await f.adapter.getConfirmedReceiptEdit(
          result.receiptId,
        )).draft.lines.single.description,
        'Coffee Brand Original 26g',
      );
    },
  );

  test(
    'confirmation checks owned image bytes before moving evidence to confirmed',
    () async {
      final a = await f.adapter.savePendingReceipt(
        await f.draft(),
        operationId: 'save',
      );
      final pending = await f.adapter.getPendingReceipt(a.id);
      await File(pending.draft.imagePath).writeAsBytes([1, 2, 3]);
      await expectLater(
        f.adapter.confirmPendingReceipt(
          a.id,
          expectedRevision: 1,
          operationId: 'confirm',
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(await f.count('receipts'), 0);
      expect(await f.count('pending_receipts'), 1);
    },
  );

  test(
    'conversion excludes its own pending but detects unrelated duplicates',
    () async {
      final draft = await f.draft();
      final a = await f.adapter.savePendingReceipt(draft, operationId: 'a');
      draft.allowDuplicate = true;
      final b = await f.adapter.savePendingReceipt(draft, operationId: 'b');
      await expectLater(
        f.adapter.confirmPendingReceipt(
          a.id,
          expectedRevision: 1,
          operationId: 'confirm',
        ),
        throwsA(isA<DuplicateReceiptException>()),
      );
      expect(await f.count('receipts'), 0);
      final result = await f.adapter.confirmPendingReceipt(
        b.id,
        expectedRevision: 1,
        operationId: 'confirm-b',
      );
      expect(result.receiptId, isNotEmpty);
      expect(await f.count('pending_receipts'), 1);
    },
  );

  test(
    'mock confirms edits and retains original confirmation operation result',
    () async {
      final adapter = MockReseeboDataAdapter();
      final draft = await f.draft();
      final pending = await adapter.savePendingReceipt(
        draft,
        operationId: 'save',
      );
      final saved = await adapter.confirmPendingReceipt(
        pending.id,
        expectedRevision: 1,
        operationId: 'confirm',
      );
      final edit = await adapter.getConfirmedReceiptEdit(saved.receiptId);
      final corrected = edit.draft;
      corrected.lines.single.grossAmountCents = 130000;
      final correction = await adapter.savePendingReceipt(
        corrected,
        operationId: 'edit',
        correctionOfReceiptId: saved.receiptId,
        expectedConfirmedRevision: 1,
      );
      await adapter.confirmPendingReceipt(
        correction.id,
        expectedRevision: 1,
        operationId: 'correct',
      );
      final retry = await adapter.confirmPendingReceipt(
        pending.id,
        expectedRevision: 1,
        operationId: 'confirm',
      );
      expect(retry.unitCostsCents, [10000]);
      expect(
        (await adapter.getConfirmedReceiptEdit(saved.receiptId)).revision,
        2,
      );
      expect(
        (await adapter.getReceipt(saved.receiptId)).lines.single.id,
        saved.lineIds.single,
      );
      expect(
        (await adapter.getReceiptRevisions(
          saved.receiptId,
        )).single.draft.lines.single.grossAmountCents,
        100000,
      );
      expect(
        await adapter.resolveConfirmedReceiptId(pending.id),
        saved.receiptId,
      );
      expect(
        (await adapter.getProductComparison(
          (await adapter.getConfirmedReceiptEdit(
            saved.receiptId,
          )).draft.lines.single.productId!,
        )).history.single.purchase.netAmountCents,
        130000,
      );
    },
  );

  test(
    'initial direct save retry after correction returns original result',
    () async {
      final draft = await f.draft();
      final saved = await f.adapter.saveConfirmedReceipt(draft);
      final edit = await f.adapter.getConfirmedReceiptEdit(saved.receiptId);
      final corrected = edit.draft;
      corrected.lines.single.grossAmountCents = 130000;
      final pending = await f.adapter.savePendingReceipt(
        corrected,
        operationId: 'edit',
        correctionOfReceiptId: saved.receiptId,
        expectedConfirmedRevision: 1,
      );
      await f.adapter.confirmPendingReceipt(
        pending.id,
        expectedRevision: 1,
        operationId: 'correct',
      );
      final retry = await f.adapter.saveConfirmedReceipt(draft);
      expect(retry.unitCostsCents, [10000]);
      expect(retry.lineIds, saved.lineIds);
      expect(retry.alreadySaved, isTrue);
    },
  );

  test(
    'independent pending commands can confirm explicit duplicate imports of one draft',
    () async {
      final draft = await f.draft();
      draft.allowDuplicate = true;
      final a = await f.adapter.savePendingReceipt(
        draft,
        operationId: 'save-a',
      );
      final first = await f.adapter.confirmPendingReceipt(
        a.id,
        expectedRevision: 1,
        operationId: 'confirm-a',
      );
      final b = await f.adapter.savePendingReceipt(
        draft,
        operationId: 'save-b',
      );
      final second = await f.adapter.confirmPendingReceipt(
        b.id,
        expectedRevision: 1,
        operationId: 'confirm-b',
      );
      expect(second.receiptId, isNot(first.receiptId));
      expect(await f.count('receipts'), 2);
    },
  );

  test('confirmation operation cannot reuse another command kind', () async {
    final a = await f.adapter.savePendingReceipt(
      await f.draft(),
      operationId: 'save',
    );
    await expectLater(
      f.adapter.confirmPendingReceipt(
        a.id,
        expectedRevision: 1,
        operationId: 'save',
      ),
      throwsA(isA<ValidationException>()),
    );
    expect(await f.count('receipts'), 0);
    expect(await f.count('pending_receipts'), 1);
  });

  test(
    'legacy direct operation retry retains original result after correction',
    () async {
      final draft = await f.draft();
      final first = await f.adapter.saveConfirmedReceipt(draft);
      await f.db.delete(
        'receipt_write_operations',
        where: 'operation_id = ?',
        whereArgs: [draft.operationId],
      );
      final edit = await f.adapter.getConfirmedReceiptEdit(first.receiptId);
      final corrected = edit.draft;
      corrected.lines.single.grossAmountCents = 130000;
      final pending = await f.adapter.savePendingReceipt(
        corrected,
        operationId: 'edit',
        correctionOfReceiptId: first.receiptId,
        expectedConfirmedRevision: 1,
      );
      await f.adapter.confirmPendingReceipt(
        pending.id,
        expectedRevision: 1,
        operationId: 'correct',
      );
      final retry = await f.adapter.saveConfirmedReceipt(draft);
      expect(retry.unitCostsCents, [10000]);
      expect(retry.alreadySaved, isTrue);
    },
  );

  test(
    'legacy receipt operation ID conflicts with pending save and confirm commands',
    () async {
      final draft = await f.draft();
      await f.adapter.saveConfirmedReceipt(draft);
      await f.db.delete(
        'receipt_write_operations',
        where: 'operation_id = ?',
        whereArgs: [draft.operationId],
      );
      await expectLater(
        f.adapter.savePendingReceipt(
          await f.draft(),
          operationId: draft.operationId,
        ),
        throwsA(isA<ValidationException>()),
      );
      final pending = await f.adapter.savePendingReceipt(
        await f.draft(),
        operationId: 'pending',
      );
      await expectLater(
        f.adapter.confirmPendingReceipt(
          pending.id,
          expectedRevision: 1,
          operationId: draft.operationId,
        ),
        throwsA(isA<ValidationException>()),
      );
    },
  );

  test(
    'concurrent confirmation commands return one original result in SQLite and mock',
    () async {
      for (final adapter in <IReseeboDataAdapter>[
        f.adapter,
        MockReseeboDataAdapter(),
      ]) {
        final draft = await f.draft();
        draft.allowDuplicate = true;
        final pending = await adapter.savePendingReceipt(
          draft,
          operationId: 'save',
        );
        final results = await Future.wait([
          adapter.confirmPendingReceipt(
            pending.id,
            expectedRevision: 1,
            operationId: 'a',
          ),
          adapter.confirmPendingReceipt(
            pending.id,
            expectedRevision: 1,
            operationId: 'b',
          ),
        ]);
        expect(results[0].receiptId, results[1].receiptId);
        expect(results[0].lineIds, results[1].lineIds);
        expect((await adapter.getLedgerEntries(query: 'Supplier A')).length, 1);
      }
    },
  );

  test(
    'mock caller mutation cannot alter frozen confirmation retry results',
    () async {
      final adapter = MockReseeboDataAdapter();
      final pending = await adapter.savePendingReceipt(
        await f.draft(),
        operationId: 'save',
      );
      final first = await adapter.confirmPendingReceipt(
        pending.id,
        expectedRevision: 1,
        operationId: 'confirm',
      );
      final lineId = first.lineIds.single;
      first.lineIds.add('caller mutation');
      first.unitCostsCents[0] = 1;
      final retry = await adapter.confirmPendingReceipt(
        pending.id,
        expectedRevision: 1,
        operationId: 'confirm',
      );
      expect(retry.lineIds, [lineId]);
      expect(retry.unitCostsCents, [10000]);
    },
  );

  test(
    'mock direct receipt edit normalizes legacy discount without false extracted fields',
    () async {
      final adapter = MockReseeboDataAdapter();
      final draft = await f.draft(amount: 4200);
      draft.lines.single.discountCents = 1000;
      final saved = await adapter.saveConfirmedReceipt(draft);
      final edit = await adapter.getConfirmedReceiptEdit(saved.receiptId);
      expect(edit.draft.lines.single.grossAmountCents, 3200);
      expect(edit.draft.lines.single.discountCents, 0);
      expect(edit.draft.lines.single.normalizedDiscountCents, 1000);
      expect(edit.draft.lines.single.extractedAmountCents, isNull);
    },
  );
}
