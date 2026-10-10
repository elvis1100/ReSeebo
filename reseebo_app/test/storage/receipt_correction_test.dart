import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/i_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/services/receipt_suggestion_service.dart';

import 'receipt_confirmation_fixture.dart';

void main() {
  late ReceiptConfirmationFixture f;
  late String initialPendingId;
  setUp(() async {
    f = ReceiptConfirmationFixture();
    await f.setUp();
  });
  tearDown(() => f.tearDown());

  Future<SaveReceiptResult> initial() async {
    final pending = await f.adapter.savePendingReceipt(
      await f.draft(),
      operationId: 'save',
    );
    initialPendingId = pending.id;
    return f.adapter.confirmPendingReceipt(
      pending.id,
      expectedRevision: 1,
      operationId: 'confirm',
    );
  }

  test(
    'direct correction lookup survives restart and clears on confirmation',
    () async {
      final saved = await initial();
      expect(await f.adapter.getPendingCorrection(saved.receiptId), isNull);
      final edit = await f.adapter.getConfirmedReceiptEdit(saved.receiptId);
      final pending = await f.adapter.savePendingReceipt(
        edit.draft..lines.single.grossAmountCents = 130000,
        operationId: 'lookup-correction',
        correctionOfReceiptId: saved.receiptId,
        expectedConfirmedRevision: edit.revision,
      );
      await f.adapter.close();
      await f.reopen();
      final found = await f.adapter.getPendingCorrection(saved.receiptId);
      expect(found!.id, pending.id);
      expect(found.revision, pending.revision);
      expect(found.draft.lines.single.grossAmountCents, 130000);
      await f.adapter.confirmPendingReceipt(
        found.id,
        expectedRevision: found.revision,
        operationId: 'lookup-confirm',
      );
      expect(await f.adapter.getPendingCorrection(saved.receiptId), isNull);
    },
  );

  test(
    'correction_preserves_recorded_order_and_images and one active purchase',
    () async {
      final first = await initial();
      final before = (await f.db.query('receipts')).single;
      final beforeLine = (await f.db.query('purchase_lines')).single;
      final edit = await f.adapter.getConfirmedReceiptEdit(first.receiptId);
      final draft = edit.draft;
      draft.lines.single.grossAmountCents = 130000;
      f.now = DateTime.utc(2027);
      final pending = await f.adapter.savePendingReceipt(
        draft,
        operationId: 'correction-save',
        correctionOfReceiptId: first.receiptId,
        expectedConfirmedRevision: edit.revision,
      );
      expect(
        (await f.adapter.getProductComparison(
          draft.lines.single.productId!,
        )).latestPrices.single.purchase.netAmountCents,
        100000,
      );
      final corrected = await f.adapter.confirmPendingReceipt(
        pending.id,
        expectedRevision: 1,
        operationId: 'correction-confirm',
      );
      expect(corrected.receiptId, first.receiptId);
      expect(corrected.lineIds, first.lineIds);
      expect(corrected.unitCostsCents, [13000]);
      final after = (await f.db.query('receipts')).single;
      expect(after['created_at'], before['created_at']);
      expect(after['recorded_order'], before['recorded_order']);
      expect(
        (await f.db.query('purchase_lines')).single['sequence'],
        beforeLine['sequence'],
      );
      expect(after['image_path'], before['image_path']);
      expect(await File(after['image_path'] as String).exists(), isTrue);
      expect(await f.count('receipts'), 1);
      expect(await f.count('purchase_lines'), 1);
      expect(
        (await f.adapter.getProductComparison(
          draft.lines.single.productId!,
        )).latestPrices.single.purchase.netAmountCents,
        130000,
      );
      expect(
        (await f.adapter.getConfirmedReceiptEdit(first.receiptId)).revision,
        2,
      );
    },
  );

  test(
    'prior_revision_is_immutable and original OCR evidence survives restart',
    () async {
      final first = await initial();
      final draft = (await f.adapter.getConfirmedReceiptEdit(
        first.receiptId,
      )).draft;
      draft.lines.single.grossAmountCents = 130000;
      draft.rawText = 'NEW RAW EVIDENCE';
      final pending = await f.adapter.savePendingReceipt(
        draft,
        operationId: 'correction-save',
        correctionOfReceiptId: first.receiptId,
        expectedConfirmedRevision: 1,
      );
      await f.adapter.confirmPendingReceipt(
        pending.id,
        expectedRevision: 1,
        operationId: 'correction-confirm',
      );
      await f.adapter.close();
      await f.reopen();
      final history = await f.adapter.getReceiptRevisions(first.receiptId);
      expect(history.single.revision, 1);
      expect(history.single.draft.lines.single.grossAmountCents, 100000);
      expect(history.single.draft.rawText, 'COFFEE ORIGINAL OCR');
      expect(history.single.draft.lines.single.extractedAmountCents, 100000);
      history.single.draft.lines.single.grossAmountCents = 1;
      expect(
        (await f.adapter.getReceiptRevisions(
          first.receiptId,
        )).single.draft.lines.single.grossAmountCents,
        100000,
      );
      final retry = await f.adapter.confirmPendingReceipt(
        pending.id,
        expectedRevision: 1,
        operationId: 'correction-confirm',
      );
      expect(retry.unitCostsCents, [13000]);
      expect(await f.count('receipt_revisions'), 1);
      final initialRetry = await f.adapter.confirmPendingReceipt(
        initialPendingId,
        expectedRevision: 1,
        operationId: 'confirm',
      );
      expect(initialRetry.unitCostsCents, [10000]);
    },
  );

  test(
    'invalid correction preserves prior purchase pending and media',
    () async {
      final first = await initial();
      final draft = (await f.adapter.getConfirmedReceiptEdit(
        first.receiptId,
      )).draft;
      draft.lines.single.quantity = 0;
      final pending = await f.adapter.savePendingReceipt(
        draft,
        operationId: 'correction-save',
        correctionOfReceiptId: first.receiptId,
        expectedConfirmedRevision: 1,
      );
      await expectLater(
        f.adapter.confirmPendingReceipt(
          pending.id,
          expectedRevision: 1,
          operationId: 'correction-confirm',
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(
        (await f.db.query('purchase_lines')).single['net_amount_cents'],
        100000,
      );
      expect(
        (await f.adapter.getPendingReceipt(
          pending.id,
        )).draft.lines.single.quantity,
        0,
      );
      expect(await File(draft.imagePath).exists(), isTrue);
      expect(await f.count('receipt_revisions'), 0);
    },
  );

  test('stale_correction_does_not_replace_purchase', () async {
    final first = await initial();
    final draft = (await f.adapter.getConfirmedReceiptEdit(
      first.receiptId,
    )).draft;
    draft.lines.single.grossAmountCents = 130000;
    final pending = await f.adapter.savePendingReceipt(
      draft,
      operationId: 'correction-save',
      correctionOfReceiptId: first.receiptId,
      expectedConfirmedRevision: 1,
    );
    await f.db.update(
      'receipt_evidence',
      {'revision': 2},
      where: 'receipt_id = ?',
      whereArgs: [first.receiptId],
    );
    await expectLater(
      f.adapter.confirmPendingReceipt(
        pending.id,
        expectedRevision: 1,
        operationId: 'correction-confirm',
      ),
      throwsA(isA<RevisionConflictException>()),
    );
    expect(
      (await f.db.query('purchase_lines')).single['net_amount_cents'],
      100000,
    );
    expect(await f.count('pending_receipts'), 1);
  });

  test(
    'correction failure rolls back updated purchase and prior revision archive',
    () async {
      final first = await initial();
      final draft = (await f.adapter.getConfirmedReceiptEdit(
        first.receiptId,
      )).draft;
      draft.lines.single.grossAmountCents = 130000;
      final pending = await f.adapter.savePendingReceipt(
        draft,
        operationId: 'correction-save',
        correctionOfReceiptId: first.receiptId,
        expectedConfirmedRevision: 1,
      );
      await f.db.execute(
        "CREATE TRIGGER fail_evidence BEFORE UPDATE ON receipt_evidence BEGIN SELECT RAISE(ABORT, 'injected archive failure'); END",
      );
      await expectLater(
        f.adapter.confirmPendingReceipt(
          pending.id,
          expectedRevision: 1,
          operationId: 'correction-confirm',
        ),
        throwsA(isA<Exception>()),
      );
      expect(
        (await f.db.query('purchase_lines')).single['net_amount_cents'],
        100000,
      );
      expect(await f.count('receipt_revisions'), 0);
      expect(await f.count('pending_receipts'), 1);
    },
  );

  test(
    'legacy confirmed edit uses stored lines and photos without extracted provenance',
    () async {
      final first = await f.adapter.saveConfirmedReceipt(await f.draft());
      final edit = await f.adapter.getConfirmedReceiptEdit(first.receiptId);
      expect(edit.revision, 1);
      expect(edit.draft.lines.single.id, first.lineIds.single);
      expect(edit.draft.lines.single.extractedAmountCents, isNull);
      expect(
        edit.draft.lines.single.provenance.values.any(
          (p) => p.origin == ReceiptFieldOrigin.extracted,
        ),
        isFalse,
      );
      expect(
        edit.draft.imagePaths,
        (await f.adapter.getReceipt(first.receiptId)).receipt.imagePaths,
      );
    },
  );

  test('corrected product removes unsupported old supplier alias', () async {
    const a = Product(
      id: 'a',
      name: 'Coffee',
      brand: 'Brand A',
      variant: 'Original',
      size: '26g',
    );
    const b = Product(
      id: 'b',
      name: 'Coffee',
      brand: 'Brand B',
      variant: 'Original',
      size: '26g',
    );
    await f.adapter.saveProduct(a);
    await f.adapter.saveProduct(b);
    final pending = await f.adapter.savePendingReceipt(
      await f.draft(productId: a.id),
      operationId: 'save',
    );
    final first = await f.adapter.confirmPendingReceipt(
      pending.id,
      expectedRevision: 1,
      operationId: 'confirm',
    );
    final edit = await f.adapter.getConfirmedReceiptEdit(first.receiptId);
    final draft = edit.draft;
    draft.lines.single.productId = b.id;
    draft.lines.single.provenance[ReceiptSuggestionField.product] =
        const ReceiptFieldProvenance(
          origin: ReceiptFieldOrigin.ownerEdited,
          explanation: 'Owner corrected exact brand.',
        );
    final correction = await f.adapter.savePendingReceipt(
      draft,
      operationId: 'correction-save',
      correctionOfReceiptId: first.receiptId,
      expectedConfirmedRevision: 1,
    );
    await f.adapter.confirmPendingReceipt(
      correction.id,
      expectedRevision: 1,
      operationId: 'correction-confirm',
    );
    final aliases = await f.db.query('supplier_product_aliases');
    expect(aliases.map((r) => r['product_id']).toList(), ['b']);
    expect((await f.adapter.getProductComparison('a')).history, isEmpty);
    expect(
      (await f.adapter.getProductComparison('b')).history.single.purchase.id,
      first.lineIds.single,
    );
    expect(
      (await f.adapter.getReceiptRevisions(
        first.receiptId,
      )).single.draft.lines.single.productId,
      'a',
    );
  });

  test(
    'alias correction preserves competing alias supported by another confirmed receipt',
    () async {
      for (final id in ['a', 'b', 'c']) {
        await f.adapter.saveProduct(
          Product(
            id: id,
            name: 'Coffee',
            brand: 'Brand $id',
            variant: 'Original',
            size: '26g',
          ),
        );
      }
      final first = await f.adapter.saveConfirmedReceipt(
        await f.draft(productId: 'a'),
      );
      await f.adapter.saveConfirmedReceipt(await f.draft(productId: 'b'));
      final edit = await f.adapter.getConfirmedReceiptEdit(first.receiptId);
      final draft = edit.draft;
      draft.lines.single.productId = 'c';
      draft.lines.single.provenance[ReceiptSuggestionField.product] =
          const ReceiptFieldProvenance(
            origin: ReceiptFieldOrigin.ownerEdited,
            explanation: 'Owner corrected exact brand.',
          );
      final pending = await f.adapter.savePendingReceipt(
        draft,
        operationId: 'edit',
        correctionOfReceiptId: first.receiptId,
        expectedConfirmedRevision: 1,
      );
      await f.adapter.confirmPendingReceipt(
        pending.id,
        expectedRevision: 1,
        operationId: 'correct',
      );
      final aliases = (await f.db.query(
        'supplier_product_aliases',
      )).map((r) => r['product_id']).toSet();
      expect(aliases, {'b', 'c'});
      expect(await f.count('receipts'), 2);
    },
  );

  test(
    'replacing correction photo retains previous original in immutable history',
    () async {
      final first = await initial();
      final edit = await f.adapter.getConfirmedReceiptEdit(first.receiptId);
      final old = edit.draft;
      final replacement = ReceiptDraft(
        operationId: 'new-photo',
        imagePath: await f.photo(),
        supplierId: old.supplierId,
        supplierName: old.supplierName,
        supplierBranch: old.supplierBranch,
        purchasedAt: old.purchasedAt,
        dateConfirmed: true,
        lines: old.lines,
        rawText: 'NEW PHOTO',
      );
      final pending = await f.adapter.savePendingReceipt(
        replacement,
        operationId: 'edit',
        correctionOfReceiptId: first.receiptId,
        expectedConfirmedRevision: 1,
      );
      await f.adapter.confirmPendingReceipt(
        pending.id,
        expectedRevision: 1,
        operationId: 'correct',
      );
      final current = (await f.adapter.getConfirmedReceiptEdit(
        first.receiptId,
      )).draft;
      final prior = (await f.adapter.getReceiptRevisions(
        first.receiptId,
      )).single.draft;
      expect(current.imagePath, isNot(old.imagePath));
      expect(prior.imagePath, old.imagePath);
      expect(await File(prior.imagePath).exists(), isTrue);
      expect(await File(current.imagePath).exists(), isTrue);
      expect(prior.rawText, 'COFFEE ORIGINAL OCR');
    },
  );

  test(
    'legacy discount edit uses payable amount once through correction and restart',
    () async {
      final draft = await f.draft(amount: 4200);
      draft.lines.single.discountCents = 1000;
      final first = await f.adapter.saveConfirmedReceipt(draft);
      final edit = await f.adapter.getConfirmedReceiptEdit(first.receiptId);
      final corrected = edit.draft;
      expect(corrected.lines.single.grossAmountCents, 3200);
      expect(corrected.lines.single.discountCents, 0);
      expect(corrected.lines.single.normalizedDiscountCents, 1000);
      expect(corrected.lines.single.extractedAmountCents, isNull);
      corrected.lines.single.quantity = 20;
      final pending = await f.adapter.savePendingReceipt(
        corrected,
        operationId: 'edit',
        correctionOfReceiptId: first.receiptId,
        expectedConfirmedRevision: 1,
      );
      final result = await f.adapter.confirmPendingReceipt(
        pending.id,
        expectedRevision: 1,
        operationId: 'correct',
      );
      expect(result.unitCostsCents, [160]);
      await f.adapter.close();
      await f.reopen();
      final current = (await f.adapter.getConfirmedReceiptEdit(
        first.receiptId,
      )).draft.lines.single;
      expect(current.netAmountCents, 3200);
      expect(current.normalizedDiscountCents, 1000);
      final prior = (await f.adapter.getReceiptRevisions(
        first.receiptId,
      )).single.draft.lines.single;
      expect(prior.netAmountCents, 3200);
      expect(prior.quantity, 10);
    },
  );

  test(
    'correction updates quantity supplier and date while retaining actual line identity',
    () async {
      final first = await initial();
      final beforeLine = (await f.db.query('purchase_lines')).single;
      final edit = await f.adapter.getConfirmedReceiptEdit(first.receiptId);
      final draft = edit.draft;
      draft.supplierId = null;
      draft.supplierName = 'Supplier B';
      draft.purchasedAt = DateTime(2026, 10, 8, 14, 30);
      draft.hasPurchaseTime = true;
      draft.lines.single.quantity = 20;
      final pending = await f.adapter.savePendingReceipt(
        draft,
        operationId: 'edit',
        correctionOfReceiptId: first.receiptId,
        expectedConfirmedRevision: 1,
      );
      await f.adapter.confirmPendingReceipt(
        pending.id,
        expectedRevision: 1,
        operationId: 'correct',
      );
      final detail = await f.adapter.getReceipt(first.receiptId);
      expect(detail.lines.single.id, first.lineIds.single);
      expect(detail.lines.single.sequence, beforeLine['sequence']);
      expect(detail.lines.single.quantity, 20);
      expect(detail.lines.single.costPerPieceCents, 5000);
      expect(detail.receipt.supplier.name, 'Supplier B');
      expect(detail.receipt.purchasedAt, DateTime(2026, 10, 8, 14, 30));
      expect(
        (await f.adapter.getReceiptRevisions(
          first.receiptId,
        )).single.draft.supplierName,
        'Supplier A',
      );
    },
  );

  test(
    'new correction rows retain older receipt place in chronological ties',
    () async {
      const a = Product(
        id: 'a',
        name: 'Coffee',
        brand: 'Brand A',
        variant: 'Original',
        size: '26g',
      );
      await f.adapter.saveProduct(a);
      final olderDraft = await f.draft(productId: 'a', amount: 100000);
      final older = await f.adapter.saveConfirmedReceipt(olderDraft);
      final newer = await f.adapter.saveConfirmedReceipt(
        await f.draft(productId: 'a', amount: 200000),
      );
      final edit = await f.adapter.getConfirmedReceiptEdit(older.receiptId);
      final correctionDraft = edit.draft;
      correctionDraft.lines.add(
        ParsedLineItem(
          id: 'new-row',
          description: 'Coffee Brand Original 26g',
          productId: 'a',
          quantity: 10,
          unit: PurchaseUnit.piece,
          piecesPerPack: 1,
          grossAmountCents: 300000,
          confirmed: true,
        ),
      );
      final correction = await f.adapter.savePendingReceipt(
        correctionDraft,
        operationId: 'correction-save',
        correctionOfReceiptId: older.receiptId,
        expectedConfirmedRevision: 1,
      );
      await f.adapter.confirmPendingReceipt(
        correction.id,
        expectedRevision: 1,
        operationId: 'correction-confirm',
      );
      final comparison = await f.adapter.getProductComparison('a');
      expect(
        comparison.latestPrices.single.purchase.receiptId,
        newer.receiptId,
      );
      expect(comparison.latestPrices.single.purchase.netAmountCents, 200000);
      expect(
        (await f.adapter.getLatestProductCosts(['a']))['a']!.costPerPieceCents,
        20000,
      );
      expect(
        (await f.adapter.calculateRestock(
          productId: 'a',
          targetPieces: 10,
          additionalCost: 0,
        )).suppliers.single.purchase.receiptId,
        newer.receiptId,
      );
      expect(
        (await f.db.query(
          'purchase_lines',
          where: 'id = ?',
          whereArgs: [older.lineIds.single],
        )).single['sequence'],
        1,
      );
    },
  );

  test(
    'cross supplier recorded ties preserve dashboard and history suggestion ordering',
    () async {
      const product = Product(
        id: 'a',
        name: 'Coffee',
        brand: 'Brand A',
        variant: 'Original',
        size: '26g',
      );
      await f.adapter.saveProduct(product);
      final older = await f.adapter.saveConfirmedReceipt(
        await f.draft(productId: 'a', amount: 100000),
      );
      final newerDraft = await f.draft(productId: 'a', amount: 200000);
      newerDraft.supplierName = 'Supplier B';
      await f.adapter.saveConfirmedReceipt(newerDraft);
      final edit = await f.adapter.getConfirmedReceiptEdit(older.receiptId);
      final correctionDraft = edit.draft;
      correctionDraft.lines.add(
        ParsedLineItem(
          id: 'new-row',
          description: 'Coffee Brand Original 26g',
          productId: 'a',
          quantity: 10,
          unit: PurchaseUnit.piece,
          piecesPerPack: 1,
          grossAmountCents: 300000,
          confirmed: true,
        ),
      );
      final pending = await f.adapter.savePendingReceipt(
        correctionDraft,
        operationId: 'edit',
        correctionOfReceiptId: older.receiptId,
        expectedConfirmedRevision: 1,
      );
      await f.adapter.confirmPendingReceipt(
        pending.id,
        expectedRevision: 1,
        operationId: 'correct',
      );
      expect(
        (await f.adapter.getLatestProductCosts(['a']))['a']!.costPerPieceCents,
        20000,
      );
      final comparison = await f.adapter.getProductComparison('a');
      final missing = await f.draft(productId: 'a');
      missing.supplierName = 'Supplier C';
      missing.lines.single.grossAmountCents = null;
      missing.lines.single.extractedAmountCents = null;
      final suggested = ReceiptSuggestionService().suggest(
        missing,
        products: [product],
        confirmedHistory: comparison.history.map((p) => p.purchase).toList(),
        importedAt: DateTime(2026, 10, 10),
      );
      expect(suggested.lines.single.grossAmountCents, 200000);
      expect(
        suggested
            .lines
            .single
            .provenance[ReceiptSuggestionField.amount]!
            .origin,
        ReceiptFieldOrigin.history,
      );
    },
  );

  test(
    'page order and all OCR media roles survive confirmation and revision archive',
    () async {
      final firstPhoto = await f.photo();
      final secondPhoto = await f.photo();
      final recognition = await f.photo();
      final comparison = await f.photo();
      final seed = await f.draft();
      final draft = ReceiptDraft(
        operationId: 'pages',
        imagePath: firstPhoto,
        imagePaths: [firstPhoto, secondPhoto],
        recognitionImagePath: recognition,
        supplierName: seed.supplierName,
        purchasedAt: seed.purchasedAt,
        dateConfirmed: true,
        lines: seed.lines,
        ocrPages: [
          ReceiptOcrPage(
            imagePath: firstPhoto,
            recognitionImagePath: recognition,
            comparisonImagePath: comparison,
            textLines: const [OcrTextLine(text: 'Recognized', left: 1, top: 2)],
            originalTextLines: const [
              OcrTextLine(text: 'Original', left: 2, top: 3),
            ],
          ),
          ReceiptOcrPage(imagePath: secondPhoto, textLines: const []),
        ],
      );
      final pending = await f.adapter.savePendingReceipt(
        draft,
        operationId: 'save',
      );
      final savedEvidence = (await f.adapter.getPendingReceipt(
        pending.id,
      )).draft;
      final first = await f.adapter.confirmPendingReceipt(
        pending.id,
        expectedRevision: 1,
        operationId: 'confirm',
      );
      final edit = await f.adapter.getConfirmedReceiptEdit(first.receiptId);
      expect(edit.draft.imagePaths, savedEvidence.imagePaths);
      expect(edit.draft.ocrPages.first.textLines.single.left, 1);
      final corrected = edit.draft;
      corrected.notes = 'Correction';
      final correction = await f.adapter.savePendingReceipt(
        corrected,
        operationId: 'correction-save',
        correctionOfReceiptId: first.receiptId,
        expectedConfirmedRevision: 1,
      );
      await f.adapter.confirmPendingReceipt(
        correction.id,
        expectedRevision: 1,
        operationId: 'correction-confirm',
      );
      final history = (await f.adapter.getReceiptRevisions(
        first.receiptId,
      )).single.draft;
      expect(history.imagePaths, savedEvidence.imagePaths);
      expect(
        history.mediaEvidence.first.recognition!.path,
        savedEvidence.mediaEvidence.first.recognition!.path,
      );
      expect(
        history.mediaEvidence.first.comparison!.path,
        savedEvidence.mediaEvidence.first.comparison!.path,
      );
      expect(history.ocrPages.first.originalTextLines.single.text, 'Original');
      for (final path in [
        history.imagePaths.first,
        history.imagePaths.last,
        history.mediaEvidence.first.recognition!.path,
        history.mediaEvidence.first.comparison!.path,
      ]) {
        expect(await File(path).exists(), isTrue);
      }
    },
  );
}
