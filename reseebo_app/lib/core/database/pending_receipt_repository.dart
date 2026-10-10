import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../errors/app_exception.dart';
import '../models/models.dart';
import '../models/pending_receipt.dart';
import '../services/local_file_store.dart';
import '../services/receipt_snapshot_codec.dart';

/// The adapter owns serialization, including copies and cleanup. This repository
/// opens one transaction per save; executor-aware read/check methods also work
/// within the later confirmation writer's existing transaction.
class PendingReceiptRepository {
  PendingReceiptRepository(
    this.database,
    this.files, {
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final Database database;
  final LocalFileStore files;
  final DateTime Function() clock;
  final ReceiptSnapshotCodec codec = ReceiptSnapshotCodec();

  static String key(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  static String supplierDisplay(ReceiptDraft draft) =>
      draft.supplierName.trim().isEmpty
      ? 'Unknown supplier'
      : [
          draft.supplierName.trim(),
          draft.supplierBranch.trim(),
        ].where((v) => v.isNotEmpty).join(' · ');

  Future<PendingReceipt> getPendingReceipt(
    String id, {
    DatabaseExecutor? executor,
  }) async {
    final rows = await (executor ?? database).query(
      'pending_receipts',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) {
      throw const ValidationException('This pending receipt was not found.');
    }
    return pendingFromRow(rows.single);
  }

  /// Confirmation verifies actual encoded bytes/dimensions for every retained
  /// coordinate space before reusing media owned by the pending save.
  Future<ReceiptDraft> verifyOwnedMedia(ReceiptDraft draft) async {
    validateDraft(draft);
    final described = await _describe(draft.snapshot());
    for (final page in described.mediaEvidence) {
      for (final ref in [page.original, page.recognition, page.comparison]) {
        if (ref != null && !files.owns(ref.path)) {
          throw const ValidationException(
            'Pending receipt media must be stored locally before confirmation.',
          );
        }
      }
    }
    return described;
  }

  Future<String?> resolveConfirmedReceiptId(String pendingId) async {
    final links = await database.query(
      'ledger_entry_links',
      columns: ['confirmed_receipt_id'],
      where: 'pending_id = ?',
      whereArgs: [pendingId],
    );
    return links.isEmpty
        ? null
        : links.single['confirmed_receipt_id'] as String;
  }

  PendingReceipt pendingFromRow(Map<String, Object?> row) {
    if (row['snapshot_version'] != ReceiptSnapshotCodec.version) {
      throw const ReceiptSnapshotException(
        'This receipt snapshot version is not supported.',
      );
    }
    return PendingReceipt(
      id: row['id'] as String,
      revision: row['revision'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at'] as int,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at'] as int,
        isUtc: true,
      ),
      draft: codec.decode(row['snapshot_payload'] as String),
      correctionOfReceiptId: row['correction_of_receipt_id'] as String?,
      baseConfirmedRevision: row['base_confirmed_revision'] as int?,
    );
  }

  /// Legacy confirmed receipts start at revision one until full evidence exists.
  Future<int> confirmedRevision(
    DatabaseExecutor executor,
    String receiptId,
  ) async {
    final rows = await executor.query(
      'receipts',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [receiptId],
    );
    if (rows.isEmpty) {
      throw const RevisionConflictException(
        'The confirmed receipt no longer exists.',
      );
    }
    final evidence = await executor.query(
      'receipt_evidence',
      columns: ['revision'],
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
    );
    return evidence.isEmpty ? 1 : evidence.single['revision'] as int;
  }

  Future<PendingSaveResult> savePendingReceipt(
    ReceiptDraft input, {
    required String operationId,
    String? pendingId,
    int? expectedRevision,
    String? correctionOfReceiptId,
    int? expectedConfirmedRevision,
  }) async {
    final draft = input.snapshot();
    if (operationId.trim().isEmpty) {
      throw const ValidationException('A save operation ID is required.');
    }
    validateDraft(draft);
    final prior = await database.query(
      'receipt_write_operations',
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
    final command = <String, Object?>{
      'pendingId': pendingId,
      'expectedRevision': expectedRevision,
      'correctionOfReceiptId': correctionOfReceiptId,
      'expectedConfirmedRevision': expectedConfirmedRevision,
    };
    if (prior.isEmpty &&
        (await database.query(
          'receipts',
          columns: ['id'],
          where: 'operation_id = ?',
          whereArgs: [operationId],
        )).isNotEmpty) {
      throw const ValidationException(
        'This operation ID was used for a confirmed save. Use a new operation ID.',
      );
    }
    if (prior.isNotEmpty) {
      if (prior.single['kind'] != 'pending_save') {
        throw const ValidationException(
          'This operation ID was used for a different action.',
        );
      }
      final prepared = await _describe(
        draft,
        retryAliases:
            jsonDecode(prior.single['request_media_payload'] as String)
                as List<dynamic>,
      );
      if (_digest(prepared, command) != prior.single['canonical_digest']) {
        throw const ValidationException(
          'This save operation already has different details. Use a new operation ID for edits.',
        );
      }
      return PendingSaveResult(
        id: prior.single['target_id'] as String,
        revision: prior.single['result_revision'] as int,
        alreadySaved: true,
      );
    }
    final current = await _checkRevision(
      database,
      pendingId,
      expectedRevision,
      correctionOfReceiptId,
      expectedConfirmedRevision,
    );
    final prepared = await _describe(draft);
    final digest = _digest(prepared, command);
    final correction = correctionOfReceiptId ?? current?.correctionOfReceiptId;
    final baseRevision =
        expectedConfirmedRevision ?? current?.baseConfirmedRevision;
    await checkDuplicates(
      database,
      prepared,
      pendingId: pendingId,
      correctionOfReceiptId: correction,
    );
    final copies = <StoredLocalFile>[];
    try {
      final stored = await _persist(prepared, copies, prior: current?.draft);
      final id = pendingId ?? const Uuid().v4();
      final revision = (current?.revision ?? 0) + 1;
      final now = clock().toUtc().millisecondsSinceEpoch;
      await database.transaction((txn) async {
        await _checkRevision(
          txn,
          pendingId,
          expectedRevision,
          correctionOfReceiptId,
          expectedConfirmedRevision,
        );
        await checkDuplicates(
          txn,
          prepared,
          pendingId: pendingId,
          correctionOfReceiptId: correction,
        );
        final values = <String, Object?>{
          'snapshot_version': ReceiptSnapshotCodec.version,
          'snapshot_payload': codec.encode(stored),
          'revision': revision,
          'updated_at': now,
          'supplier_name_key': key(draft.supplierName),
          'supplier_branch_key': key(draft.supplierBranch),
          'receipt_number_key': key(draft.receiptNumber),
          'search_text': searchText(draft),
          'correction_of_receipt_id': correction,
          'base_confirmed_revision': baseRevision,
        };
        if (current == null) {
          await txn.insert('pending_receipts', {
            'id': id,
            ...values,
            'created_at': now,
          });
        } else {
          await txn.update(
            'pending_receipts',
            values,
            where: 'id = ? AND revision = ?',
            whereArgs: [id, expectedRevision],
          );
          await txn.delete(
            'pending_receipt_images',
            where: 'pending_id = ?',
            whereArgs: [id],
          );
        }
        for (var page = 0; page < stored.mediaEvidence.length; page++) {
          final original = stored.mediaEvidence[page].original;
          await txn.insert('pending_receipt_images', {
            'pending_id': id,
            'page_index': page,
            'image_path': original.path,
            'image_hash': original.sha256,
          });
        }
        if (correction != null) {
          await txn.insert('ledger_entry_links', {
            'pending_id': id,
            'confirmed_receipt_id': correction,
            'created_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        await txn.insert('receipt_write_operations', {
          'operation_id': operationId,
          'kind': 'pending_save',
          'canonical_digest': digest,
          'target_id': id,
          'result_revision': revision,
          'result_payload': jsonEncode({'id': id, 'revision': revision}),
          'request_media_payload': jsonEncode(_aliases(prepared, stored)),
          'created_at': now,
        });
      });
      // Old owned evidence stays readable for future confirmation/revision history.
      return PendingSaveResult(id: id, revision: revision);
    } catch (_) {
      for (final copy in copies) {
        if (copy.created) await files.remove(copy.path);
      }
      rethrow;
    }
  }

  Future<PendingReceipt?> _checkRevision(
    DatabaseExecutor executor,
    String? id,
    int? expected,
    String? correction,
    int? expectedConfirmed,
  ) async {
    PendingReceipt? current;
    if (id == null) {
      if (expected != null) {
        throw const ValidationException(
          'A new pending receipt cannot have an expected revision.',
        );
      }
    } else {
      final rows = await executor.query(
        'pending_receipts',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty ||
          expected == null ||
          rows.single['revision'] != expected) {
        throw const RevisionConflictException();
      }
      current = pendingFromRow(rows.single);
      if ((correction != null && correction != current.correctionOfReceiptId) ||
          (expectedConfirmed != null &&
              expectedConfirmed != current.baseConfirmedRevision)) {
        throw const RevisionConflictException(
          'A correction cannot change its original confirmed receipt or revision.',
        );
      }
    }
    final source = correction ?? current?.correctionOfReceiptId;
    final base = expectedConfirmed ?? current?.baseConfirmedRevision;
    if ((source == null) != (base == null)) {
      throw const ValidationException(
        'A correction requires its confirmed receipt and revision.',
      );
    }
    if (source != null) {
      if (await confirmedRevision(executor, source) != base) {
        throw const RevisionConflictException();
      }
      final other = await executor.query(
        'pending_receipts',
        columns: ['id'],
        where: 'correction_of_receipt_id = ?',
        whereArgs: [source],
      );
      if (other.any((r) => r['id'] != id)) {
        throw const RevisionConflictException(
          'This receipt already has a pending correction. Open that correction.',
        );
      }
    }
    return current;
  }

  /// Unresolved/invalid purchase values remain evidence. This boundary validates
  /// DTO shape, ordered pages and links; confirmation owns whole-piece validity.
  static void validateDraft(ReceiptDraft draft) {
    if (draft.imagePaths.isEmpty ||
        draft.imagePaths.length > maxReceiptPages ||
        draft.imagePaths.any((p) => p.trim().isEmpty) ||
        draft.imagePath != draft.imagePaths.first) {
      throw const ValidationException('Choose 1 to 20 ordered receipt photos.');
    }
    if (draft.lines.length > 1000 ||
        draft.lines.any(
          (l) =>
              l.id.trim().isEmpty ||
              l.sourcePage < 0 ||
              l.sourcePage >= draft.imagePaths.length,
        ) ||
        draft.lines.map((l) => l.id).toSet().length != draft.lines.length) {
      throw const ValidationException(
        'Receipt lines require unique IDs and valid source pages, with at most 1,000 lines.',
      );
    }
    if (draft.ocrPages.isNotEmpty &&
            draft.ocrPages.length != draft.imagePaths.length ||
        draft.mediaEvidence.isNotEmpty &&
            draft.mediaEvidence.length != draft.imagePaths.length) {
      throw const ValidationException(
        'Receipt evidence must align with every ordered photo.',
      );
    }
    for (var i = 0; i < draft.imagePaths.length; i++) {
      final page = draft.ocrPages.isEmpty ? null : draft.ocrPages[i];
      final media = draft.mediaEvidence.isEmpty ? null : draft.mediaEvidence[i];
      if (page != null && page.imagePath != draft.imagePaths[i] ||
          media != null && media.original.path != draft.imagePaths[i] ||
          page?.recognitionImagePath != null &&
              media?.recognition != null &&
              page!.recognitionImagePath != media!.recognition!.path ||
          page?.comparisonImagePath != null &&
              media?.comparison != null &&
              page!.comparisonImagePath != media!.comparison!.path ||
          i == 0 &&
              draft.recognitionImagePath != null &&
              page?.recognitionImagePath != null &&
              draft.recognitionImagePath != page!.recognitionImagePath ||
          i == 0 &&
              draft.recognitionImagePath != null &&
              media?.recognition != null &&
              draft.recognitionImagePath != media!.recognition!.path) {
        throw const ValidationException(
          'Receipt image paths and coordinate evidence do not align.',
        );
      }
    }
  }

  Future<ReceiptDraft> _describe(
    ReceiptDraft draft, {
    List<dynamic> retryAliases = const [],
  }) async {
    final pages = <ReceiptPageMedia>[];
    final described = <String, ReceiptImageReference>{};
    Future<ReceiptImageReference> describe(
      String path,
      ReceiptImageReference? supplied,
      String preprocessing,
    ) async {
      ReceiptImageReference ref;
      if (described.containsKey(path)) {
        final old = described[path]!;
        ref = ReceiptImageReference(
          path: path,
          sha256: old.sha256,
          width: old.width,
          height: old.height,
          preprocessingIdentity: preprocessing,
        );
      } else if (await File(path).exists()) {
        final bytes = await File(path).readAsBytes();
        image.Image? pixels;
        try {
          pixels = image.decodeImage(bytes);
        } on Object {
          pixels = null;
        }
        if (pixels == null || pixels.width < 1 || pixels.height < 1) {
          throw const ValidationException(
            'Choose a readable encoded receipt image.',
          );
        }
        ref = ReceiptImageReference(
          path: path,
          sha256: sha256.convert(bytes).toString(),
          width: pixels.width,
          height: pixels.height,
          preprocessingIdentity: preprocessing,
        );
        described[path] = ref;
      } else {
        final aliases = retryAliases.where(
          (a) => a is Map && (a['paths'] as List<dynamic>).contains(path),
        );
        if (aliases.isEmpty) {
          throw const ValidationException(
            'A receipt image is missing. Select it again.',
          );
        }
        final alias = aliases.first as Map;
        ref = ReceiptImageReference(
          path: path,
          sha256: alias['sha256'] as String,
          width: alias['width'] as int,
          height: alias['height'] as int,
          preprocessingIdentity: preprocessing,
        );
      }
      if (supplied != null &&
          (supplied.sha256 != ref.sha256 ||
              supplied.width != ref.width ||
              supplied.height != ref.height ||
              supplied.path != path)) {
        throw const ValidationException(
          'Receipt image evidence does not describe the selected image bytes.',
        );
      }
      return ref;
    }

    final identity = draft.ocrRun?.preprocessingRevision ?? '1';
    final hashes = <String>{};
    for (var i = 0; i < draft.imagePaths.length; i++) {
      final page = draft.ocrPages.isEmpty ? null : draft.ocrPages[i];
      final media = draft.mediaEvidence.isEmpty ? null : draft.mediaEvidence[i];
      final original = await describe(
        draft.imagePaths[i],
        media?.original,
        media?.original.preprocessingIdentity ?? 'original',
      );
      if (!hashes.add(original.sha256)) {
        throw const ValidationException(
          'The same image cannot be saved as two receipt pages.',
        );
      }
      final recognitionPath =
          page?.recognitionImagePath ??
          (i == 0 ? draft.recognitionImagePath : null) ??
          media?.recognition?.path;
      final comparisonPath =
          page?.comparisonImagePath ?? media?.comparison?.path;
      pages.add(
        ReceiptPageMedia(
          original: original,
          recognition: recognitionPath == null
              ? null
              : await describe(
                  recognitionPath,
                  media?.recognition,
                  media?.recognition?.preprocessingIdentity ?? identity,
                ),
          comparison: comparisonPath == null
              ? null
              : await describe(
                  comparisonPath,
                  media?.comparison,
                  media?.comparison?.preprocessingIdentity ?? identity,
                ),
        ),
      );
    }
    return withMedia(draft, pages);
  }

  /// Reconstructs final path fields through the strict DTO, preserving all other
  /// editable and evidence values. Task6 can reuse this for confirmed evidence.
  ReceiptDraft withMedia(ReceiptDraft draft, List<ReceiptPageMedia> pages) {
    final payload = codec.toMap(draft);
    final d = payload['draft'] as Map<String, Object?>;
    d['imagePath'] = pages.first.original.path;
    d['imagePaths'] = pages.map((p) => p.original.path).toList();
    // Retain the legacy nullable recognition field's presence independently.
    d['recognitionImagePath'] = draft.recognitionImagePath == null
        ? null
        : pages.first.recognition?.path;
    d['mediaEvidence'] = pages.map(ReceiptSnapshotCodec.mediaToMap).toList();
    final ocrPages = d['ocrPages'] as List<Map<String, Object?>>;
    for (var i = 0; i < ocrPages.length; i++) {
      ocrPages[i]['imagePath'] = pages[i].original.path;
      ocrPages[i]['recognitionImagePath'] =
          draft.ocrPages[i].recognitionImagePath == null
          ? null
          : pages[i].recognition?.path;
      ocrPages[i]['comparisonImagePath'] =
          draft.ocrPages[i].comparisonImagePath == null
          ? null
          : pages[i].comparison?.path;
    }
    return codec.fromMap(payload);
  }

  String _digest(ReceiptDraft draft, Map<String, Object?> command) {
    ReceiptImageReference canonical(ReceiptImageReference r) =>
        ReceiptImageReference(
          path: 'sha256:${r.sha256}',
          sha256: r.sha256,
          width: r.width,
          height: r.height,
          preprocessingIdentity: r.preprocessingIdentity,
        );
    final pages = draft.mediaEvidence
        .map(
          (p) => ReceiptPageMedia(
            original: canonical(p.original),
            recognition: p.recognition == null
                ? null
                : canonical(p.recognition!),
            comparison: p.comparison == null ? null : canonical(p.comparison!),
          ),
        )
        .toList();
    return sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'command': command,
              'snapshot': codec.toMap(withMedia(draft, pages)),
            }),
          ),
        )
        .toString();
  }

  Future<ReceiptDraft> _persist(
    ReceiptDraft draft,
    List<StoredLocalFile> copies, {
    ReceiptDraft? prior,
  }) async {
    final reused = <String, ReceiptImageReference>{};
    final checkedPaths = <String, String>{};
    for (final page in prior?.mediaEvidence ?? <ReceiptPageMedia>[]) {
      final refs = {
        'original': page.original,
        'recognition': page.recognition,
        'comparison': page.comparison,
      };
      for (final entry in refs.entries) {
        final ref = entry.value;
        if (ref == null ||
            !files.owns(ref.path) ||
            !await File(ref.path).exists()) {
          continue;
        }
        final digest = checkedPaths[ref.path] ?? await files.hash(ref.path);
        checkedPaths[ref.path] = digest;
        if (digest == ref.sha256) {
          reused['${entry.key}:${ref.sha256}'] = ref;
        }
      }
    }
    Future<ReceiptImageReference?> persist(
      ReceiptImageReference? r,
      String role,
    ) async {
      if (r == null) return null;
      final contentRole = '$role:${r.sha256}';
      final earlier = reused[contentRole];
      if (earlier != null) {
        return ReceiptImageReference(
          path: earlier.path,
          sha256: r.sha256,
          width: r.width,
          height: r.height,
          preprocessingIdentity: r.preprocessingIdentity,
        );
      }
      final copy = await files.persist(
        r.path,
        category: role == 'original' ? 'receipts' : 'receipt_$role',
        existingPath: files.owns(r.path) ? r.path : null,
      );
      copies.add(copy);
      if (copy.hash != r.sha256) {
        throw const ValidationException(
          'An image changed while saving. Select the receipt again.',
        );
      }
      final stored = ReceiptImageReference(
        path: copy.path,
        sha256: copy.hash,
        width: r.width,
        height: r.height,
        preprocessingIdentity: r.preprocessingIdentity,
      );
      reused[contentRole] = stored;
      return stored;
    }

    final pages = <ReceiptPageMedia>[];
    for (final page in draft.mediaEvidence) {
      pages.add(
        ReceiptPageMedia(
          original: (await persist(page.original, 'original'))!,
          recognition: await persist(page.recognition, 'recognition'),
          comparison: await persist(page.comparison, 'comparison'),
        ),
      );
    }
    return withMedia(draft, pages);
  }

  List<Map<String, Object?>> _aliases(
    ReceiptDraft source,
    ReceiptDraft stored,
  ) {
    final aliases = <Map<String, Object?>>[];
    for (var i = 0; i < source.mediaEvidence.length; i++) {
      final src = source.mediaEvidence[i];
      final dest = stored.mediaEvidence[i];
      final sources = [src.original, src.recognition, src.comparison];
      final targets = [dest.original, dest.recognition, dest.comparison];
      for (var role = 0; role < sources.length; role++) {
        final ref = sources[role];
        if (ref != null) {
          aliases.add({
            'paths': [ref.path, targets[role]!.path],
            'sha256': ref.sha256,
            'width': ref.width,
            'height': ref.height,
          });
        }
      }
    }
    return aliases;
  }

  Future<void> checkDuplicates(
    DatabaseExecutor executor,
    ReceiptDraft draft, {
    String? pendingId,
    String? correctionOfReceiptId,
  }) async {
    if (draft.allowDuplicate) return;
    final hashes = draft.mediaEvidence.map((p) => p.original.sha256).toList();
    final placeholders = List.filled(hashes.length, '?').join(',');
    final name = key(draft.supplierName);
    final branch = key(draft.supplierBranch);
    final number = key(draft.receiptNumber);
    final confirmed = await executor.rawQuery(
      '''SELECT DISTINCT r.id FROM receipts r
      JOIN suppliers s ON s.id = r.supplier_id JOIN receipt_images i ON i.receipt_id = r.id
      WHERE (i.image_hash IN ($placeholders) OR (? != '' AND ? != '' AND s.name_key = ? AND s.branch_key = ? AND r.receipt_number_key = ?))
      AND r.id != ? ORDER BY r.id''',
      [
        ...hashes,
        name,
        number,
        name,
        branch,
        number,
        correctionOfReceiptId ?? '',
      ],
    );
    final pending = await executor.rawQuery(
      '''SELECT DISTINCT p.id FROM pending_receipts p
      JOIN pending_receipt_images i ON i.pending_id = p.id
      WHERE (i.image_hash IN ($placeholders) OR (? != '' AND ? != '' AND p.supplier_name_key = ? AND p.supplier_branch_key = ? AND p.receipt_number_key = ?))
      AND p.id != ? ORDER BY p.id''',
      [...hashes, name, number, name, branch, number, pendingId ?? ''],
    );
    final ids = {
      ...confirmed.map((r) => r['id'] as String),
      ...pending.map((r) => r['id'] as String),
    }.toList()..sort();
    if (ids.isNotEmpty) {
      throw DuplicateReceiptException(ids);
    }
  }

  static String searchText(ReceiptDraft draft) => [
    draft.supplierName,
    draft.supplierBranch,
    draft.receiptNumber,
    draft.notes,
    draft.rawText,
    ...draft.lines.map((l) => l.description),
  ].join(' ');
  static String _like(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');
  Future<List<LedgerEntry>> getLedgerEntries({
    int limit = 200,
    String? query,
  }) async {
    if (limit < 1 || limit > 1000) {
      throw const ValidationException(
        'Choose a receipt limit between 1 and 1,000.',
      );
    }
    final value = query?.trim() ?? '';
    final rows = await database.rawQuery(
      '''SELECT * FROM (
      SELECT r.id AS id, r.created_at AS recorded_at,
        CASE WHEN p.id IS NULL THEN 'confirmed' ELSE 'needsReview' END AS status,
        s.name || CASE WHEN s.branch = '' THEN '' ELSE ' · ' || s.branch END AS supplier_display,
        r.total_cents AS total_cents, r.id AS confirmed_id, p.id AS pending_id,
        p.snapshot_payload AS pending_payload,
        s.name || ' ' || s.branch || ' ' || r.receipt_number || ' ' || r.notes || ' ' || r.raw_text || ' ' ||
        COALESCE((SELECT group_concat(l.original_description || ' ' || pr.name, ' ') FROM purchase_lines l
          JOIN products pr ON pr.id = l.product_id WHERE l.receipt_id = r.id), '') || ' ' || COALESCE(p.search_text, '') AS search_text
      FROM receipts r JOIN suppliers s ON s.id = r.supplier_id
      LEFT JOIN pending_receipts p ON p.correction_of_receipt_id = r.id
      UNION ALL
      SELECT p.id, p.created_at, 'needsReview', '', NULL, NULL, p.id, p.snapshot_payload, p.search_text
      FROM pending_receipts p WHERE p.correction_of_receipt_id IS NULL
    ) WHERE search_text LIKE ? ESCAPE '\\' ORDER BY recorded_at DESC, id ASC LIMIT ?''',
      ['%${_like(value)}%', limit],
    );
    return rows.map((r) {
      final pending = r['pending_payload'] == null
          ? null
          : codec.decode(r['pending_payload'] as String);
      return LedgerEntry(
        id: r['id'] as String,
        status: r['status'] == 'confirmed'
            ? LedgerEntryStatus.confirmed
            : LedgerEntryStatus.needsReview,
        recordedAt: DateTime.fromMillisecondsSinceEpoch(
          r['recorded_at'] as int,
          isUtc: true,
        ),
        supplierDisplay: pending == null
            ? r['supplier_display'] as String
            : supplierDisplay(pending),
        provisionalTotalCents: pending == null
            ? r['total_cents'] as int?
            : pending.detectedTotalCents,
        confirmedReceiptId: r['confirmed_id'] as String?,
        pendingId: r['pending_id'] as String?,
      );
    }).toList();
  }
}
