import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/i_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';

void main() {
  late MockReseeboDataAdapter adapter;
  setUp(() {
    adapter = MockReseeboDataAdapter();
  });

  ReceiptDraft confirmed({
    String path = 'new-original',
    String number = '',
    String? productId,
  }) => ReceiptDraft(
    operationId: 'confirmed-operation',
    imagePath: path,
    supplierId: 'sup_a',
    supplierName: 'Puregold Price Club',
    supplierBranch: 'Branch A - San Juan',
    purchasedAt: DateTime(2026, 10, 10),
    dateConfirmed: true,
    receiptNumber: number,
    rawText: 'Raw OCR keyword receipt-evidence',
    lines: [
      ParsedLineItem(
        id: 'line',
        description: 'Printed description line-evidence',
        productId: productId,
        quantity: 1,
        unit: PurchaseUnit.piece,
        piecesPerPack: 1,
        grossAmountCents: 2100,
        confirmed: true,
      ),
    ],
  );

  Future<void> expectRejectedWithoutMutations(
    ReceiptDraft draft,
    String pendingId,
  ) async {
    final products = await adapter.getProducts();
    final receipts = await adapter.getRecentReceipts();
    final suppliers = await adapter.getSuppliers();
    await expectLater(
      adapter.saveConfirmedReceipt(draft),
      throwsA(
        isA<DuplicateReceiptException>().having(
          (e) => e.receiptIds,
          'pending duplicate',
          [pendingId],
        ),
      ),
    );
    expect(
      (await adapter.getProducts()).map((p) => p.id),
      products.map((p) => p.id),
    );
    expect(
      (await adapter.getRecentReceipts()).map((r) => r.id),
      receipts.map((r) => r.id),
    );
    expect(
      (await adapter.getSuppliers()).map((s) => s.id),
      suppliers.map((s) => s.id),
    );
    expect((await adapter.getPendingReceipt(pendingId)).id, pendingId);
    expect(draft.lines.single.productId, isNull);
  }

  test(
    'mock confirmed ledger searches private line, current product name and original OCR evidence',
    () async {
      const product = Product(
        id: 'evidence-product',
        name: 'Catalog product-evidence',
        brand: 'Brand',
        variant: 'Original',
        size: '26g',
      );
      await adapter.saveProduct(product);
      final draft = confirmed(productId: product.id);
      final saved = await adapter.saveConfirmedReceipt(draft);
      draft.rawText = 'changed after save';
      draft.lines.single.description = 'changed after save';
      for (final query in [
        'LINE-EVIDENCE',
        'receipt-evidence',
        'product-evidence',
      ]) {
        final entries = await adapter.getLedgerEntries(query: query);
        expect(entries.map((e) => e.confirmedReceiptId), [
          saved.receiptId,
        ], reason: query);
        expect(entries.single.status, LedgerEntryStatus.confirmed);
      }
      await adapter.saveProduct(
        product.copyWith(name: 'Renamed revised-product'),
      );
      expect(
        (await adapter.getLedgerEntries(
          query: 'revised-product',
        )).single.confirmedReceiptId,
        saved.receiptId,
      );
      expect(
        await adapter.getLedgerEntries(query: 'changed after save'),
        isEmpty,
      );
      expect(await adapter.getLedgerEntries(query: '%'), isEmpty);
    },
  );

  test(
    'mock correction entry remains searchable by confirmed line and raw OCR evidence',
    () async {
      final source = await adapter.saveConfirmedReceipt(confirmed());
      final correction = await adapter.savePendingReceipt(
        ReceiptDraft(
          imagePath: 'replacement-original',
          notes: 'pending correction-evidence',
        ),
        operationId: 'correction',
        correctionOfReceiptId: source.receiptId,
        expectedConfirmedRevision: 1,
      );
      for (final query in [
        'line-evidence',
        'receipt-evidence',
        'correction-evidence',
      ]) {
        final entry = (await adapter.getLedgerEntries(query: query)).single;
        expect(entry.id, source.receiptId, reason: query);
        expect(entry.pendingId, correction.id);
        expect(entry.confirmedReceiptId, source.receiptId);
        expect(entry.status, LedgerEntryStatus.needsReview);
      }
      expect(
        (await adapter.getLedgerEntries()).length,
        (await adapter.getRecentReceipts()).length,
      );
    },
  );

  test(
    'mock fixture ledger searches available purchase descriptions and product names',
    () async {
      expect(
        (await adapter.getLedgerEntries(
          query: '10s',
        )).map((e) => e.confirmedReceiptId),
        ['rec_001'],
      );
      expect(
        (await adapter.getLedgerEntries(
          query: 'Promo',
        )).map((e) => e.confirmedReceiptId),
        ['rec_004'],
      );
      expect(
        (await adapter.getLedgerEntries(
          query: 'Brand X Original Coffee 26g',
        )).map((e) => e.confirmedReceiptId),
        ['rec_001', 'rec_002', 'rec_003', 'rec_004'],
      );
    },
  );

  test(
    'mock direct confirmed original-path duplicate rejects before catalog mutations',
    () async {
      final pending = await adapter.savePendingReceipt(
        ReceiptDraft(imagePath: 'pending-original'),
        operationId: 'pending',
      );
      await expectRejectedWithoutMutations(
        confirmed(path: 'pending-original'),
        pending.id,
      );
    },
  );

  test(
    'mock direct confirmed supplier branch number duplicate rejects before catalog mutations',
    () async {
      final pending = await adapter.savePendingReceipt(
        ReceiptDraft(
          imagePath: 'different-pending-original',
          supplierName: '  puregold  price club ',
          supplierBranch: 'branch a - san juan',
          receiptNumber: ' or-new ',
        ),
        operationId: 'pending',
      );
      await expectRejectedWithoutMutations(
        confirmed(number: 'OR-NEW'),
        pending.id,
      );
    },
  );

  test(
    'mock direct confirmed explicit duplicate override retains pending and adds one purchase',
    () async {
      final pending = await adapter.savePendingReceipt(
        ReceiptDraft(
          imagePath: 'pending-original',
          supplierName: 'Puregold Price Club',
          supplierBranch: 'Branch A - San Juan',
          receiptNumber: 'OR-NEW',
        ),
        operationId: 'pending',
      );
      final products = (await adapter.getProducts()).length;
      final receipts = (await adapter.getRecentReceipts()).length;
      final draft = confirmed(path: 'pending-original', number: 'OR-NEW')
        ..allowDuplicate = true;
      final result = await adapter.saveConfirmedReceipt(draft);
      expect((await adapter.getProducts()).length, products + 1);
      expect((await adapter.getRecentReceipts()).length, receipts + 1);
      expect((await adapter.getPendingReceipt(pending.id)).id, pending.id);
      expect(
        (await adapter.getRecentReceipts()).any(
          (r) => r.id == result.receiptId,
        ),
        isTrue,
      );
    },
  );

  for (final entry in {
    'unknown supplier': '',
    'other branch': 'Puregold Price Club',
    'missing number': 'Puregold Price Club',
  }.entries) {
    test('mock direct confirmed number evidence skips ${entry.key}', () async {
      await adapter.savePendingReceipt(
        ReceiptDraft(
          imagePath: 'different-pending-original',
          supplierName: entry.value,
          supplierBranch: entry.key == 'other branch'
              ? 'Other branch'
              : 'Branch A - San Juan',
          receiptNumber: entry.key == 'missing number' ? '' : 'OR-NEW',
        ),
        operationId: 'pending',
      );
      final before = (await adapter.getRecentReceipts()).length;
      await adapter.saveConfirmedReceipt(confirmed(number: 'OR-NEW'));
      expect((await adapter.getRecentReceipts()).length, before + 1);
    });
  }
}
