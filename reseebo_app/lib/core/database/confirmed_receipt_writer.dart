import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../errors/app_exception.dart';
import '../models/models.dart';
import '../services/local_file_store.dart';
import '../services/receipt_validator.dart';
import 'pending_receipt_repository.dart';

/// Writes validated active purchases inside the caller's serialized transaction.
/// Images must already be persisted/verified by that caller. This writer opens
/// neither a transaction nor a write queue and never deletes image files.
class ConfirmedReceiptWriter {
  ConfirmedReceiptWriter({
    required this.images,
    required this.operationId,
    required this.digest,
    required this.clock,
    this.pendingId,
    this.recordedAt,
  });
  final List<StoredLocalFile> images;
  final String operationId;
  final String digest;
  final DateTime Function() clock;
  final String? pendingId;
  final int? recordedAt;

  Future<SaveReceiptResult> write(
    DatabaseExecutor executor,
    ReceiptDraft snapshot, {
    String? replacingReceiptId,
  }) async {
    final draft = snapshot.snapshot();
    ReceiptValidator.validate(draft);
    if (images.length != draft.imagePaths.length ||
        images.isEmpty ||
        images.map((p) => p.hash).toSet().length != images.length) {
      throw const ValidationException(
        'Keep unique ordered original receipt photos.',
      );
    }
    for (final id
        in draft.lines.map((l) => l.productId).whereType<String>().toSet()) {
      if ((await executor.query(
        'products',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [id],
      )).isEmpty) {
        throw const ValidationException(
          'A selected product no longer exists. Confirm the product matches again.',
        );
      }
    }
    final now = clock().toUtc().millisecondsSinceEpoch;
    final suppliers = await executor.query(
      'suppliers',
      where: draft.supplierId == null
          ? 'name_key = ? AND branch_key = ?'
          : 'id = ?',
      whereArgs: draft.supplierId == null
          ? [_key(draft.supplierName), _key(draft.supplierBranch)]
          : [draft.supplierId],
    );
    if (draft.supplierId != null &&
        (suppliers.isEmpty ||
            suppliers.first['name_key'] != _key(draft.supplierName) ||
            suppliers.first['branch_key'] != _key(draft.supplierBranch))) {
      throw const ValidationException(
        'The selected supplier changed. Choose its branch again.',
      );
    }
    final supplierId = suppliers.isEmpty
        ? const Uuid().v4()
        : suppliers.first['id'] as String;
    if (suppliers.isEmpty) {
      await executor.insert('suppliers', {
        'id': supplierId,
        'name': draft.supplierName.trim(),
        'branch': draft.supplierBranch.trim(),
        'notes': draft.supplierNotes.trim(),
        'name_key': _key(draft.supplierName),
        'branch_key': _key(draft.supplierBranch),
        'created_at': now,
        'updated_at': now,
      });
    }
    final number = _key(draft.receiptNumber);
    if (!draft.allowDuplicate) {
      final marks = List.filled(images.length, '?').join(',');
      final confirmed = await executor.rawQuery(
        '''SELECT DISTINCT r.id FROM receipts r
        JOIN receipt_images i ON i.receipt_id = r.id
        WHERE (i.image_hash IN ($marks) OR (r.supplier_id = ? AND r.receipt_number_key = ? AND r.receipt_number_key != ''))
        AND r.id != ?''',
        [
          ...images.map((p) => p.hash),
          supplierId,
          number,
          replacingReceiptId ?? '',
        ],
      );
      final pending = await executor.rawQuery(
        '''SELECT DISTINCT p.id FROM pending_receipts p
        JOIN pending_receipt_images i ON i.pending_id = p.id
        WHERE (i.image_hash IN ($marks) OR (p.supplier_name_key = ? AND p.supplier_branch_key = ? AND p.receipt_number_key = ? AND p.receipt_number_key != ''))
        AND p.id != ?''',
        [
          ...images.map((p) => p.hash),
          _key(draft.supplierName),
          _key(draft.supplierBranch),
          number,
          pendingId ?? '',
        ],
      );
      final ids = {
        ...confirmed.map((r) => r['id'] as String),
        ...pending.map((r) => r['id'] as String),
      }.toList()..sort();
      if (ids.isNotEmpty) throw DuplicateReceiptException(ids);
    }
    final oldReceipt = replacingReceiptId == null
        ? <Map<String, Object?>>[]
        : await executor.query(
            'receipts',
            where: 'id = ?',
            whereArgs: [replacingReceiptId],
          );
    if (replacingReceiptId != null && oldReceipt.isEmpty) {
      throw const RevisionConflictException();
    }
    final oldLines = replacingReceiptId == null
        ? <Map<String, Object?>>[]
        : await executor.query(
            'purchase_lines',
            where: 'receipt_id = ?',
            whereArgs: [replacingReceiptId],
          );
    final oldById = {for (final l in oldLines) l['id'] as String: l};
    final receiptId = replacingReceiptId ?? const Uuid().v4();
    final date = draft.purchasedAt!;
    final values = <String, Object?>{
      'supplier_id': supplierId,
      'purchased_at':
          (draft.hasPurchaseTime
                  ? date
                  : DateTime(date.year, date.month, date.day))
              .toIso8601String(),
      'purchased_date':
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'purchase_time': draft.hasPurchaseTime
          ? '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}'
          : null,
      'has_purchase_time': draft.hasPurchaseTime ? 1 : 0,
      'image_path': images.first.path,
      'image_hash': images.first.hash,
      'receipt_number': draft.receiptNumber.trim(),
      'receipt_number_key': number,
      'notes': draft.notes.trim(),
      'raw_text': draft.rawText,
      'total_cents': draft.lines.fold<int>(
        0,
        (sum, l) => sum + l.netAmountCents!,
      ),
      'updated_at': now,
    };
    // Corrections retain the original save identity and recorded ordering.
    if (replacingReceiptId == null) {
      await executor.insert('receipts', {
        'id': receiptId,
        'operation_id': operationId,
        'content_digest': digest,
        'created_at': recordedAt ?? now,
        ...values,
      });
    } else {
      await executor.update(
        'receipts',
        values,
        where: 'id = ?',
        whereArgs: [receiptId],
      );
      await executor.delete(
        'receipt_images',
        where: 'receipt_id = ?',
        whereArgs: [receiptId],
      );
    }
    for (var page = 0; page < images.length; page++) {
      await executor.insert('receipt_images', {
        'receipt_id': receiptId,
        'page_index': page,
        'image_path': images[page].path,
        'image_hash': images[page].hash,
      });
    }
    final imported = <String, String>{};
    final lineIds = <String>[];
    final costs = <double>[];
    for (final line in draft.lines) {
      var productId = line.productId;
      if (productId == null) {
        final key = _key(line.description);
        productId = imported[key];
        if (productId == null) {
          productId = const Uuid().v4();
          imported[key] = productId;
          await executor.insert('products', {
            'id': productId,
            'name': line.description.trim(),
            'brand': '',
            'variant': '',
            'size': '',
            'name_only': 1,
            'created_at': now,
            'updated_at': now,
          });
        }
      }
      final existing = oldById[line.id];
      final lineId = existing == null ? const Uuid().v4() : line.id;
      final lineValues = <String, Object?>{
        'product_id': productId,
        'source_page': line.sourcePage,
        'original_description': line.description.trim(),
        'quantity': line.quantity,
        'unit': line.unit!.name,
        'pieces_per_pack': line.piecesPerPack,
        'total_pieces': line.totalPieces,
        'gross_amount_cents': line.grossAmountCents,
        'discount_cents': line.discountCents,
        'net_amount_cents': line.netAmountCents,
        'updated_at': now,
      };
      if (existing == null) {
        await executor.insert('purchase_lines', {
          'id': lineId,
          'receipt_id': receiptId,
          'created_at': recordedAt ?? now,
          ...lineValues,
        });
      } else {
        // Updating in place preserves both saved identity and chronological ties.
        await executor.update(
          'purchase_lines',
          lineValues,
          where: 'id = ?',
          whereArgs: [lineId],
        );
      }
      await executor.insert('supplier_product_aliases', {
        'id': const Uuid().v4(),
        'supplier_id': supplierId,
        'product_id': productId,
        'description': line.description.trim(),
        'description_key': _key(line.description),
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      lineIds.add(lineId);
      costs.add(line.netAmountCents! / line.totalPieces!);
    }
    for (final old in oldLines) {
      if (!lineIds.contains(old['id'])) {
        await executor.delete(
          'purchase_lines',
          where: 'id = ?',
          whereArgs: [old['id']],
        );
      }
    }
    if (oldReceipt.isNotEmpty) {
      // Retract only an old mapping no longer supported by any active receipt.
      // Competing mappings supported elsewhere remain ambiguous, never stolen.
      for (final old in oldLines) {
        final oldSupplier = oldReceipt.single['supplier_id'];
        final key = _key(old['original_description'] as String);
        final supporting = await executor.rawQuery(
          '''SELECT l.original_description FROM purchase_lines l
          JOIN receipts r ON r.id = l.receipt_id WHERE r.supplier_id = ? AND l.product_id = ?''',
          [oldSupplier, old['product_id']],
        );
        if (!supporting.any(
          (l) => _key(l['original_description'] as String) == key,
        )) {
          await executor.delete(
            'supplier_product_aliases',
            where: 'supplier_id = ? AND product_id = ? AND description_key = ?',
            whereArgs: [oldSupplier, old['product_id'], key],
          );
        }
      }
    }
    return SaveReceiptResult(
      receiptId: receiptId,
      lineIds: lineIds,
      unitCostsCents: costs,
    );
  }

  static String _key(String value) => PendingReceiptRepository.key(value);
}
