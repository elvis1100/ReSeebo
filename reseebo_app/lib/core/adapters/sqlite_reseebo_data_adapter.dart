import '../services/receipt_product_match.dart';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqlite;

import '../database/reseebo_database.dart';
import '../database/pending_receipt_repository.dart';
import '../database/confirmed_receipt_writer.dart';
import '../database/row_mappers.dart';
import '../services/local_file_store.dart';
import '../services/ocr_service.dart';
import '../services/ocr_engine_registry.dart';
import '../services/pricing_service.dart';
import '../services/receipt_parser.dart';
import '../services/receipt_ocr_comparison.dart';
import '../services/receipt_validator.dart';
import '../services/receipt_snapshot_codec.dart';
import '../services/starter_catalog_service.dart';
import 'i_reseebo_data_adapter.dart';

class SqliteReseeboDataAdapter implements IReseeboDataAdapter {
  @override
  Future<List<OcrEngineDescriptor>> getOcrEngines() async => _ocr.descriptors;
  @override
  Future<void> releaseOcrSession() => _ocr.releaseLoadedEngine();

  SqliteReseeboDataAdapter._(this._db, this._files, this._ocr, this._clock);
  final sqlite.Database _db;
  final LocalFileStore _files;
  final OcrEngineRegistry _ocr;
  final DateTime Function() _clock;
  final ReceiptParser _parser = ReceiptParser();
  final ReceiptSnapshotCodec _codec = ReceiptSnapshotCodec();
  late final PendingReceiptRepository _pending = PendingReceiptRepository(
    _db,
    _files,
    clock: _clock,
  );
  Future<void> _pendingWrites = Future.value();
  bool _closed = false;

  /// Defaults open the phone's private support directory. Tests inject an FFI
  /// factory, database path, media directory and OCR double, retaining real SQL.
  static Future<SqliteReseeboDataAdapter> open({
    sqlite.DatabaseFactory? databaseFactory,
    String? databasePath,
    Directory? mediaDirectory,
    OcrService? ocrService,
    OcrEngineRegistry? ocrRegistry,
    DateTime Function()? clock,
    List<Product>? starterProducts,
  }) async {
    if (ocrService != null && ocrRegistry != null) {
      throw ArgumentError('Supply an OCR service or registry, not both.');
    }
    final String dbPath;
    if (databasePath == null) {
      final support = await getApplicationSupportDirectory();
      await support.create(recursive: true);
      dbPath = p.join(support.path, 'reseebo.sqlite');
      mediaDirectory ??= Directory(p.join(support.path, 'media'));
    } else {
      dbPath = databasePath;
      mediaDirectory ??= Directory(p.join(p.dirname(dbPath), 'media'));
    }
    await mediaDirectory.create(recursive: true);
    if (dbPath != sqlite.inMemoryDatabasePath) {
      await Directory(p.dirname(dbPath)).create(recursive: true);
    }
    final db = await ReseeboDatabase.open(
      factory: databaseFactory ?? sqlite.databaseFactory,
      path: dbPath,
    );
    try {
      await StarterCatalogService.seed(
        db,
        starterProducts ?? await StarterCatalogService.load(),
        now: (clock ?? DateTime.now)(),
      );
    } catch (_) {
      await db.close();
      rethrow;
    }
    return SqliteReseeboDataAdapter._(
      db,
      LocalFileStore(mediaDirectory),
      ocrRegistry ??
          (ocrService == null
              ? await OcrEngineRegistry.loadBundled()
              : OcrEngineRegistry(mlKitService: ocrService)),
      clock ?? DateTime.now,
    );
  }

  Future<T> _write<T>(Future<T> Function() operation) {
    if (_closed) {
      return Future.error(const AppException('The local database is closed.'));
    }
    // Serializing writes includes file copies and cleanup, preventing competing
    // photo replacements from deleting a path another write is about to save.
    final result = _pendingWrites.then((_) => operation());
    _pendingWrites = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  static String _key(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  static String _like(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');
  int get _now => _clock().toUtc().millisecondsSinceEpoch;

  @override
  Future<StoreProfile> getStoreProfile() async {
    final rows = await _db.query('store_profiles', where: 'id = 1');
    return rows.isEmpty ? const StoreProfile() : profileFromRow(rows.first);
  }

  @override
  Future<void> updateStoreProfile(StoreProfile profile) => _write(() async {
    PricingService.validateMarkup(profile.defaultMarkupPercent);
    if (profile.name.trim().isEmpty) {
      throw const ValidationException('Enter your store name.');
    }
    final rows = await _db.query('store_profiles', where: 'id = 1');
    final oldPath = rows.isEmpty ? null : rows.first['photo_path'] as String?;
    StoredLocalFile? copied;
    try {
      if (profile.photoPath != null) {
        copied = await _files.persist(
          profile.photoPath!,
          category: 'store_photos',
          existingPath: oldPath,
        );
      }
      final now = _now;
      final values = <String, Object?>{
        'name': profile.name.trim(),
        'owner_name': profile.ownerName.trim(),
        'photo_path': copied?.path,
        'default_markup_percent': profile.defaultMarkupPercent,
        'updated_at': now,
      };
      if (rows.isEmpty) {
        await _db.insert('store_profiles', {
          'id': 1,
          ...values,
          'created_at': now,
        });
      } else {
        await _db.update('store_profiles', values, where: 'id = 1');
      }
    } catch (_) {
      if (copied?.created ?? false) await _files.remove(copied!.path);
      rethrow;
    }
    if (oldPath != copied?.path) await _files.remove(oldPath);
  });

  @override
  Future<List<Product>> getProducts({String? query}) async {
    final value = query?.trim() ?? '';
    final rows = await _db.query(
      'products',
      where: value.isEmpty
          ? null
          : "(name || ' ' || brand || ' ' || variant || ' ' || size || ' ' || category || ' ' || barcode) LIKE ? ESCAPE '\\'",
      whereArgs: value.isEmpty ? null : ['%${_like(value)}%'],
      orderBy: 'name COLLATE NOCASE, brand COLLATE NOCASE, size COLLATE NOCASE',
    );
    return rows.map(productFromRow).toList();
  }

  @override
  Future<Product?> getProductById(String id) async {
    final rows = await _db.query('products', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : productFromRow(rows.first);
  }

  @override
  Future<List<String>> getProductCategories() async => (await _db.rawQuery('''
    SELECT name FROM product_categories
    UNION SELECT trim(category) COLLATE NOCASE FROM products WHERE trim(category) != ''
    ORDER BY name COLLATE NOCASE
  ''')).map((row) => row['name'] as String).toList();

  @override
  Future<void> addProductCategory(String name) => _write(() async {
    final value = name.trim();
    if (value.isEmpty) {
      throw const ValidationException('Enter a category name.');
    }
    await _db.insert('product_categories', {
      'name': value,
    }, conflictAlgorithm: sqlite.ConflictAlgorithm.ignore);
  });

  @override
  Future<void> removeProductCategory(String name) => _write(() async {
    await _db.transaction((txn) async {
      await txn.update(
        'products',
        {'category': '', 'updated_at': _now},
        where: 'trim(category) = ? COLLATE NOCASE',
        whereArgs: [name.trim()],
      );
      await txn.delete(
        'product_categories',
        where: 'name = ? COLLATE NOCASE',
        whereArgs: [name.trim()],
      );
    });
  });

  @override
  Future<void> saveProduct(Product product) => _write(() async {
    if ([
      product.id,
      product.name,
      if (!product.nameOnly) ...[product.brand, product.variant, product.size],
    ].any((value) => value.trim().isEmpty)) {
      throw const ValidationException(
        'Enter the product name, brand, variant and size. Use a clear variant such as Original when applicable.',
      );
    }
    PricingService.validateMarkup(product.markupPercent);
    if (product.sellingPriceCents != null) {
      PricingService.validateMoney(product.sellingPriceCents!);
    }
    final oldRows = await _db.query(
      'products',
      where: 'id = ?',
      whereArgs: [product.id],
    );
    final old = oldRows.isEmpty ? null : productFromRow(oldRows.first);
    if (old != null && !old.nameOnly && product.nameOnly) {
      throw const ValidationException(
        'Keep the confirmed product identity. Create a separate product for a different item.',
      );
    }
    final identityChanged =
        old != null &&
        (old.nameOnly
            ? old.size.trim().isNotEmpty &&
                  (_key(old.name) != _key(product.name) ||
                      _key(old.size) != _key(product.size))
            : (_key(old.brand) != _key(product.brand) ||
                  _key(old.variant) != _key(product.variant) ||
                  _key(old.size) != _key(product.size)));
    if (identityChanged) {
      final history = await _db.query(
        'purchase_lines',
        columns: ['id'],
        where: 'product_id = ?',
        whereArgs: [product.id],
        limit: 1,
      );
      if (history.isNotEmpty) {
        throw const ValidationException(
          'This product has purchase history. Keep its identity and size, or create a separate product for a different item.',
        );
      }
    }
    StoredLocalFile? copied;
    try {
      if (product.photoPath != null &&
          !product.photoPath!.startsWith('asset:')) {
        copied = await _files.persist(
          product.photoPath!,
          category: 'product_photos',
          existingPath: old?.photoPath,
        );
      }
      final now = _now;
      final values = <String, Object?>{
        'name': product.name.trim(),
        'name_only': product.nameOnly ? 1 : 0,
        'brand': product.brand.trim(),
        'variant': product.variant.trim(),
        'size': product.size.trim(),
        'category': product.category.trim(),
        'barcode': product.barcode.trim(),
        'photo_path': product.photoPath?.startsWith('asset:') == true
            ? product.photoPath
            : copied?.path,
        'markup_percent': product.markupPercent,
        'selling_price_cents': product.sellingPriceCents,
        'updated_at': now,
      };
      await _db.transaction((txn) async {
        if (product.category.trim().isNotEmpty) {
          await txn.insert('product_categories', {
            'name': product.category.trim(),
          }, conflictAlgorithm: sqlite.ConflictAlgorithm.ignore);
        }
        if (old == null) {
          await txn.insert('products', {
            'id': product.id,
            ...values,
            'created_at': now,
          });
        } else {
          await txn.update(
            'products',
            values,
            where: 'id = ?',
            whereArgs: [product.id],
          );
        }
      });
    } catch (_) {
      if (copied?.created ?? false) await _files.remove(copied!.path);
      rethrow;
    }
    if (old?.photoPath != copied?.path) await _files.remove(old?.photoPath);
  });

  @override
  Future<List<Supplier>> getSuppliers() async => (await _db.query(
    'suppliers',
    orderBy: 'name COLLATE NOCASE, branch COLLATE NOCASE',
  )).map(supplierFromRow).toList();

  @override
  Future<Supplier?> getSupplierById(String id) async {
    final rows = await _db.query('suppliers', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : supplierFromRow(rows.first);
  }

  @override
  Future<void> saveSupplier(Supplier supplier) => _write(() async {
    if (supplier.id.trim().isEmpty || supplier.name.trim().isEmpty) {
      throw const ValidationException('Enter a supplier name.');
    }
    final duplicate = await _db.query(
      'suppliers',
      where: 'name_key = ? AND branch_key = ? AND id != ?',
      whereArgs: [_key(supplier.name), _key(supplier.branch), supplier.id],
    );
    if (duplicate.isNotEmpty) {
      throw const ValidationException(
        'This supplier branch is already saved. Select the existing supplier.',
      );
    }
    final old = await _db.query(
      'suppliers',
      where: 'id = ?',
      whereArgs: [supplier.id],
    );
    final now = _now;
    final values = <String, Object?>{
      'name': supplier.name.trim(),
      'branch': supplier.branch.trim(),
      'notes': supplier.notes.trim(),
      'date_order': supplier.dateOrder?.name,
      'name_key': _key(supplier.name),
      'branch_key': _key(supplier.branch),
      'updated_at': now,
    };
    if (old.isEmpty) {
      await _db.insert('suppliers', {
        'id': supplier.id,
        ...values,
        'created_at': now,
      });
    } else {
      final changedIdentity =
          old.first['name_key'] != _key(supplier.name) ||
          old.first['branch_key'] != _key(supplier.branch);
      if (changedIdentity) {
        final receipts = await _db.query(
          'receipts',
          columns: ['id'],
          where: 'supplier_id = ?',
          whereArgs: [supplier.id],
          limit: 1,
        );
        if (receipts.isNotEmpty) {
          throw const ValidationException(
            'This supplier has receipts. Create a separate supplier for a different business or branch.',
          );
        }
      }
      await _db.update(
        'suppliers',
        values,
        where: 'id = ?',
        whereArgs: [supplier.id],
      );
    }
  });

  @override
  Future<List<ProductMatchSuggestion>> matchAliases(
    String rawOcrDescription, {
    String? supplierId,
  }) async {
    final key = _key(rawOcrDescription);
    if (key.isEmpty) return [];
    final scoped = supplierId == null
        ? <Map<String, Object?>>[]
        : await _db.rawQuery(
            'SELECT DISTINCT p.* FROM products p JOIN supplier_product_aliases a ON a.product_id = p.id WHERE a.supplier_id = ? AND a.description_key = ?',
            [supplierId, key],
          );
    if (scoped.isNotEmpty) {
      return scoped
          .map(
            (row) => ProductMatchSuggestion(
              product: productFromRow(row),
              reason: scoped.length > 1
                  ? 'This supplier description has more than one confirmed mapping. Choose the exact variant and size.'
                  : 'Previously confirmed description for this supplier branch.',
              exactAlias: true,
            ),
          )
          .toList();
    }
    // Global aliases have no reliable supplier provenance. They can suggest a
    // product but must never silently decide which branch-specific variant wins.
    final exact = await _db.rawQuery(
      'SELECT DISTINCT p.* FROM products p JOIN product_aliases a ON a.product_id = p.id WHERE a.description_key = ?',
      [key],
    );
    final suggestions = exact
        .map(
          (row) => ProductMatchSuggestion(
            product: productFromRow(row),
            reason:
                'Saved catalog description. Confirm this supplier product and size.',
          ),
        )
        .toList();
    if (suggestions.isNotEmpty) return suggestions;
    return receiptProductSuggestions(rawOcrDescription, await getProducts());
  }

  @override
  Future<List<ProductAlias>> getAliases(String productId) async =>
      (await _db.rawQuery(
            'SELECT id, product_id, description FROM product_aliases WHERE product_id = ? UNION ALL SELECT id, product_id, description FROM supplier_product_aliases WHERE product_id = ? ORDER BY description COLLATE NOCASE',
            [productId, productId],
          ))
          .map(
            (row) => ProductAlias(
              id: row['id'] as String,
              productId: row['product_id'] as String,
              description: row['description'] as String,
            ),
          )
          .toList();

  @override
  Future<void> deleteAlias(String aliasId) => _write(() async {
    await _db.delete('product_aliases', where: 'id = ?', whereArgs: [aliasId]);
    await _db.delete(
      'supplier_product_aliases',
      where: 'id = ?',
      whereArgs: [aliasId],
    );
  });

  @override
  Future<List<Receipt>> getRecentReceipts({
    int limit = 200,
    String? query,
  }) async {
    if (limit < 1 || limit > 1000) {
      throw const ValidationException(
        'Choose a receipt limit between 1 and 1,000.',
      );
    }
    final value = query?.trim() ?? '';
    final where = value.isEmpty
        ? ''
        : " WHERE (s.name || ' ' || s.branch || ' ' || r.receipt_number || ' ' || r.notes) LIKE ? ESCAPE '\\' OR EXISTS (SELECT 1 FROM purchase_lines l JOIN products p ON p.id = l.product_id WHERE l.receipt_id = r.id AND (p.name || ' ' || l.original_description) LIKE ? ESCAPE '\\')";
    final args = <Object?>[
      if (value.isNotEmpty) ...['%${_like(value)}%', '%${_like(value)}%'],
      limit,
    ];
    final rows = await _db.rawQuery(
      '$receiptSelect$where ORDER BY r.purchased_date DESC, r.recorded_order DESC LIMIT ?',
      args,
    );
    return rows.map(receiptFromRow).toList();
  }

  @override
  Future<PendingSaveResult> savePendingReceipt(
    ReceiptDraft draft, {
    required String operationId,
    String? pendingId,
    int? expectedRevision,
    String? correctionOfReceiptId,
    int? expectedConfirmedRevision,
  }) {
    final snapshot = draft.snapshot();
    return _write(
      () => _pending.savePendingReceipt(
        snapshot,
        operationId: operationId,
        pendingId: pendingId,
        expectedRevision: expectedRevision,
        correctionOfReceiptId: correctionOfReceiptId,
        expectedConfirmedRevision: expectedConfirmedRevision,
      ),
    );
  }

  @override
  Future<PendingReceipt> getPendingReceipt(String id) =>
      _pending.getPendingReceipt(id);

  @override
  Future<PendingReceipt?> getPendingCorrection(String receiptId) =>
      _pending.getPendingCorrection(receiptId);

  @override
  Future<String?> resolveConfirmedReceiptId(String pendingId) =>
      _pending.resolveConfirmedReceiptId(pendingId);

  @override
  Future<ConfirmedReceiptEdit> getConfirmedReceiptEdit(String receiptId) =>
      _confirmedEdit(_db, receiptId);

  Future<ConfirmedReceiptEdit> _confirmedEdit(
    sqlite.DatabaseExecutor executor,
    String receiptId,
  ) async {
    final rows = await executor.rawQuery('$receiptSelect WHERE r.id = ?', [
      receiptId,
    ]);
    if (rows.isEmpty) {
      throw const ValidationException('This receipt was not found.');
    }
    final evidence = await executor.query(
      'receipt_evidence',
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
    );
    if (evidence.isNotEmpty) {
      if (evidence.single['snapshot_version'] != ReceiptSnapshotCodec.version) {
        throw const ReceiptSnapshotException(
          'This receipt snapshot version is not supported.',
        );
      }
      return ConfirmedReceiptEdit(
        receiptId: receiptId,
        revision: evidence.single['revision'] as int,
        draft: _codec.decode(evidence.single['snapshot_payload'] as String),
      );
    }
    final row = rows.single;
    final photos = await executor.query(
      'receipt_images',
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
      orderBy: 'page_index',
    );
    final lines = await executor.query(
      'purchase_lines',
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
      orderBy: 'sequence',
    );
    // Legacy purchase rows retain owner-confirmed values, but cannot establish
    // extraction provenance or recognition coordinate spaces retroactively.
    // Review edits the payable amount. Fold the old active discount once and
    // retain its original value separately so reopening cannot subtract it again.
    final draft = ReceiptDraft(
      operationId: row['operation_id'] as String,
      imagePath: row['image_path'] as String,
      imagePaths: photos.map((p) => p['image_path'] as String).toList(),
      supplierId: row['supplier_id'] as String,
      supplierName: row['supplier_name'] as String,
      supplierBranch: row['supplier_branch'] as String,
      supplierNotes: row['supplier_notes'] as String,
      purchasedAt: DateTime.parse(row['purchased_at'] as String),
      hasPurchaseTime: row['has_purchase_time'] == 1,
      dateConfirmed: true,
      receiptNumber: row['receipt_number'] as String,
      notes: row['notes'] as String,
      rawText: row['raw_text'] as String,
      lines: lines
          .map(
            (l) => ParsedLineItem(
              id: l['id'] as String,
              productId: l['product_id'] as String,
              description: l['original_description'] as String,
              quantity: l['quantity'] as int,
              unit: PurchaseUnit.values.byName(l['unit'] as String),
              piecesPerPack: l['pieces_per_pack'] as int,
              grossAmountCents: l['net_amount_cents'] as int,
              normalizedDiscountCents: l['discount_cents'] as int,
              sourcePage: l['source_page'] as int,
              confirmed: true,
            ),
          )
          .toList(),
    );
    return ConfirmedReceiptEdit(
      receiptId: receiptId,
      revision: 1,
      draft: draft,
    );
  }

  @override
  Future<List<ReceiptRevision>> getReceiptRevisions(String receiptId) async {
    await _pending.confirmedRevision(_db, receiptId);
    final rows = await _db.query(
      'receipt_revisions',
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
      orderBy: 'revision DESC',
    );
    return rows.map((r) {
      if (r['snapshot_version'] != ReceiptSnapshotCodec.version) {
        throw const ReceiptSnapshotException(
          'This receipt snapshot version is not supported.',
        );
      }
      return ReceiptRevision(
        revision: r['revision'] as int,
        recordedAt: DateTime.fromMillisecondsSinceEpoch(
          r['recorded_at'] as int,
          isUtc: true,
        ),
        draft: _codec.decode(r['snapshot_payload'] as String),
      );
    }).toList();
  }

  static Map<String, Object?> _resultPayload(SaveReceiptResult result) => {
    'receiptId': result.receiptId,
    'lineIds': result.lineIds,
    'unitCostsCents': result.unitCostsCents,
  };

  static SaveReceiptResult _operationResult(Map<String, Object?> row) {
    final result =
        jsonDecode(row['result_payload'] as String) as Map<String, dynamic>;
    return SaveReceiptResult(
      receiptId: result['receiptId'] as String,
      lineIds: List<String>.from(result['lineIds'] as List),
      unitCostsCents: (result['unitCostsCents'] as List)
          .map((n) => (n as num).toDouble())
          .toList(),
      alreadySaved: true,
    );
  }

  Future<void> _recordOperation(
    sqlite.DatabaseExecutor executor, {
    required String operationId,
    required String kind,
    required String digest,
    required String targetId,
    required int revision,
    required SaveReceiptResult result,
    List<Map<String, Object?>> media = const [],
  }) => executor
      .insert('receipt_write_operations', {
        'operation_id': operationId,
        'kind': kind,
        'canonical_digest': digest,
        'target_id': targetId,
        'result_revision': revision,
        'result_payload': jsonEncode(_resultPayload(result)),
        'request_media_payload': jsonEncode(media),
        'created_at': _now,
      })
      .then((_) {});

  @override
  Future<SaveReceiptResult> confirmPendingReceipt(
    String id, {
    required int expectedRevision,
    required String operationId,
  }) {
    if (id.trim().isEmpty ||
        operationId.trim().isEmpty ||
        expectedRevision < 1) {
      return Future.error(
        const ValidationException(
          'Choose a pending receipt revision and confirmation operation ID.',
        ),
      );
    }
    final digest = sha256
        .convert(
          utf8.encode(
            jsonEncode({'pendingId': id, 'expectedRevision': expectedRevision}),
          ),
        )
        .toString();
    return _write(
      () => _db.transaction((txn) async {
        final prior = await txn.query(
          'receipt_write_operations',
          where: 'operation_id = ?',
          whereArgs: [operationId],
        );
        if (prior.isNotEmpty) {
          final row = prior.single;
          if ((row['kind'] != 'pending_confirm' &&
                  row['kind'] != 'confirmed_correction') ||
              row['canonical_digest'] != digest) {
            throw const ValidationException(
              'This operation ID was used for a different action or receipt revision. Use a new operation ID.',
            );
          }
          return _operationResult(row);
        }
        if ((await txn.query(
          'receipts',
          columns: ['id'],
          where: 'operation_id = ?',
          whereArgs: [operationId],
        )).isNotEmpty) {
          throw const ValidationException(
            'This operation ID was used for a different confirmed save. Use a new operation ID.',
          );
        }
        // Another confirmation command may already have consumed this import.
        // The original result survives deletion and subsequent receipt revisions.
        final consumed = await txn.query(
          'receipt_write_operations',
          where:
              "target_id = ? AND kind IN ('pending_confirm', 'confirmed_correction')",
          whereArgs: [id],
          orderBy: 'created_at, operation_id',
          limit: 1,
        );
        if (consumed.isNotEmpty) {
          final row = consumed.single;
          if (row['canonical_digest'] != digest) {
            throw const RevisionConflictException();
          }
          final result = _operationResult(row);
          await _recordOperation(
            txn,
            operationId: operationId,
            kind: row['kind'] as String,
            digest: digest,
            targetId: id,
            revision: row['result_revision'] as int,
            result: result,
          );
          return result;
        }
        final pending = await _pending.getPendingReceipt(id, executor: txn);
        if (pending.revision != expectedRevision) {
          throw const RevisionConflictException();
        }
        final source = pending.correctionOfReceiptId;
        ConfirmedReceiptEdit? old;
        if (source != null) {
          old = await _confirmedEdit(txn, source);
          if (old.revision != pending.baseConfirmedRevision) {
            throw const RevisionConflictException();
          }
          final initial = (await txn.query(
            'receipts',
            where: 'id = ?',
            whereArgs: [source],
          )).single;
          // Receipts saved before operation-result storage still need their first
          // result frozen before a correction changes the active purchase rows.
          if ((await txn.query(
            'receipt_write_operations',
            columns: ['operation_id'],
            where: 'operation_id = ?',
            whereArgs: [initial['operation_id']],
          )).isEmpty) {
            final original = await _savedResult(
              txn,
              source,
              alreadySaved: false,
            );
            final images = await txn.query(
              'receipt_images',
              where: 'receipt_id = ?',
              whereArgs: [source],
              orderBy: 'page_index',
            );
            await _recordOperation(
              txn,
              operationId: initial['operation_id'] as String,
              kind: 'confirmed_save',
              digest: initial['content_digest'] as String,
              targetId: source,
              revision: 1,
              result: original,
              media: images
                  .map(
                    (p) => <String, Object?>{
                      'path': p['image_path'],
                      'hash': p['image_hash'],
                    },
                  )
                  .toList(),
            );
          }
        }
        final draft = await _pending.verifyOwnedMedia(pending.draft);
        ReceiptValidator.validate(draft);
        final images = draft.mediaEvidence
            .map(
              (p) => StoredLocalFile(
                path: p.original.path,
                hash: p.original.sha256,
                created: false,
              ),
            )
            .toList();
        final result = await ConfirmedReceiptWriter(
          images: images,
          operationId: operationId,
          digest: digest,
          clock: _clock,
          pendingId: id,
          recordedAt: source == null
              ? pending.createdAt.millisecondsSinceEpoch
              : null,
        ).write(txn, draft, replacingReceiptId: source);
        final revision = (old?.revision ?? 0) + 1;
        if (old != null) {
          await txn.insert('receipt_revisions', {
            'receipt_id': source,
            'revision': old.revision,
            'snapshot_version': ReceiptSnapshotCodec.version,
            'snapshot_payload': _codec.encode(old.draft),
            'recorded_at': _now,
          });
        }
        final evidence = await _savedEvidence(txn, draft, result);
        final evidenceValues = {
          'receipt_id': result.receiptId,
          'revision': revision,
          'snapshot_version': ReceiptSnapshotCodec.version,
          'snapshot_payload': _codec.encode(evidence),
          'updated_at': _now,
        };
        if ((await txn.query(
          'receipt_evidence',
          columns: ['receipt_id'],
          where: 'receipt_id = ?',
          whereArgs: [result.receiptId],
        )).isEmpty) {
          await txn.insert('receipt_evidence', evidenceValues);
        } else {
          await txn.update(
            'receipt_evidence',
            evidenceValues,
            where: 'receipt_id = ?',
            whereArgs: [result.receiptId],
          );
        }
        await txn.insert('ledger_entry_links', {
          'pending_id': id,
          'confirmed_receipt_id': result.receiptId,
          'created_at': _now,
        }, conflictAlgorithm: sqlite.ConflictAlgorithm.ignore);
        await _recordOperation(
          txn,
          operationId: operationId,
          kind: source == null ? 'pending_confirm' : 'confirmed_correction',
          digest: digest,
          targetId: id,
          revision: revision,
          result: result,
        );
        await txn.delete(
          'pending_receipts',
          where: 'id = ? AND revision = ?',
          whereArgs: [id, expectedRevision],
        );
        return result;
      }),
    );
  }

  Future<ReceiptDraft> _savedEvidence(
    sqlite.DatabaseExecutor executor,
    ReceiptDraft draft,
    SaveReceiptResult result,
  ) async {
    final payload = _codec.toMap(draft);
    final data = payload['draft'] as Map<String, Object?>;
    final lines = data['lines'] as List<Map<String, Object?>>;
    for (var i = 0; i < lines.length; i++) {
      final saved = (await executor.query(
        'purchase_lines',
        columns: ['product_id'],
        where: 'id = ?',
        whereArgs: [result.lineIds[i]],
      )).single;
      lines[i]['id'] = result.lineIds[i];
      lines[i]['productId'] = saved['product_id'];
    }
    final receipt = (await executor.query(
      'receipts',
      columns: ['supplier_id'],
      where: 'id = ?',
      whereArgs: [result.receiptId],
    )).single;
    data['supplierId'] = receipt['supplier_id'];
    return _codec.fromMap(payload);
  }

  @override
  Future<List<LedgerEntry>> getLedgerEntries({
    int limit = 200,
    String? query,
  }) => _pending.getLedgerEntries(limit: limit, query: query);

  @override
  Future<ReceiptDetail> getReceipt(String receiptId) async {
    final rows = await _db.rawQuery('$receiptSelect WHERE r.id = ?', [
      receiptId,
    ]);
    if (rows.isEmpty) {
      throw const ValidationException('This receipt was not found.');
    }
    final lines = await _db.rawQuery(
      '$purchaseSelect WHERE l.receipt_id = ? ORDER BY l.sequence',
      [receiptId],
    );
    final images = await _db.query(
      'receipt_images',
      columns: ['image_path'],
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
      orderBy: 'page_index',
    );
    return ReceiptDetail(
      receipt: receiptFromRow(
        rows.first,
        imagePaths: images.map((row) => row['image_path'] as String).toList(),
      ),
      lines: lines.map(purchaseFromRow).toList(),
    );
  }

  @override
  Future<ReceiptDraft> processReceiptImage(
    String localImagePath, {
    String? recognitionImagePath,
    String? comparisonImagePath,
    OcrEngineId engineId = OcrEngineId.mlKit,
  }) => processReceiptImages(
    [localImagePath],
    recognitionImagePaths: [recognitionImagePath ?? localImagePath],
    comparisonImagePaths: [comparisonImagePath ?? localImagePath],
    engineId: engineId,
  );

  @override
  Future<ReceiptDraft> processReceiptImages(
    List<String> localImagePaths, {
    List<String>? recognitionImagePaths,
    List<String>? comparisonImagePaths,
    OcrEngineId engineId = OcrEngineId.mlKit,
    String preprocessingRevision = '1',
  }) async {
    final originals = List<String>.of(localImagePaths);
    final adjusted = List<String>.of(recognitionImagePaths ?? originals);
    final comparison = List<String>.of(comparisonImagePaths ?? originals);
    if (preprocessingRevision.trim().isEmpty) {
      throw const ValidationException(
        'Provide the image preprocessing revision.',
      );
    }
    if (originals.isEmpty ||
        originals.length > maxReceiptPages ||
        adjusted.length != originals.length ||
        comparison.length != originals.length) {
      throw const ValidationException(
        'Choose 1 to 20 photos in receipt order.',
      );
    }
    final hashes = <String>{};
    final orderedHashes = <Map<String, String>>[];
    for (final path in originals) {
      final digest = await _files.hash(path);
      if (!hashes.add(digest)) {
        throw const ValidationException(
          'The same receipt photo was added twice. Remove the repeated page.',
        );
      }
      final index = orderedHashes.length;
      orderedHashes.add({
        'original': digest,
        'recognition': adjusted[index] == path
            ? digest
            : await _files.hash(adjusted[index]),
        'comparison': comparison[index] == path
            ? digest
            : await _files.hash(comparison[index]),
      });
    }
    final watch = Stopwatch()..start();
    final pages = <ReceiptOcrPage>[];
    final comparisonWarnings = <String>[];
    for (var index = 0; index < originals.length; index++) {
      try {
        final text = await _ocr.recognize(engineId, adjusted[index]);
        var originalText = <OcrTextLine>[];
        if (adjusted[index] != comparison[index]) {
          try {
            originalText = await _ocr.recognize(engineId, comparison[index]);
          } catch (_) {
            comparisonWarnings.add(
              'Photo ${index + 1}: the original photo could not be compared. Review the enhanced reading.',
            );
          }
        }
        pages.add(
          ReceiptOcrPage(
            imagePath: originals[index],
            recognitionImagePath: adjusted[index] == originals[index]
                ? null
                : adjusted[index],
            textLines: text,
            originalTextLines: originalText,
            comparisonImagePath: comparison[index],
          ),
        );
      } on AppException catch (failure) {
        throw AppException('Photo ${index + 1}: ${failure.message}');
      }
    }
    watch.stop();
    final descriptor = _ocr.descriptorFor(engineId);
    final run = OcrRunMetadata(
      engineId: engineId,
      modelVersion: descriptor.modelVersion,
      runtimeVersion: descriptor.runtimeVersion,
      parserVersion: ReceiptParser.version,
      inputDigest: sha256
          .convert(utf8.encode(jsonEncode(orderedHashes)))
          .toString(),
      preprocessingRevision: preprocessingRevision,
      elapsedMs: watch.elapsedMilliseconds,
    );
    final draft = _parser.parsePages(pages: pages, ocrRun: run);
    draft.ocrPages
      ..clear()
      ..addAll(pages);
    const ReceiptOcrComparison().supplement(draft, pages);
    for (var index = 0; index < pages.length; index++) {
      if (pages[index].originalTextLines.isNotEmpty) {
        draft.rawText +=
            '\n\n--- Original photo ${index + 1} comparison ---\n${pages[index].originalTextLines.map((line) => line.text).join('\n')}';
      }
    }
    draft.warnings.addAll(comparisonWarnings);
    return draft;
  }

  @override
  Future<SaveReceiptResult> saveConfirmedReceipt(
    ReceiptDraft confirmedDraft,
  ) async {
    final draft = confirmedDraft.snapshot();
    ReceiptValidator.validate(draft);
    final digest = _contentDigest(draft);
    return _write(() => _saveSnapshot(draft, digest));
  }

  static String _contentDigest(ReceiptDraft draft) => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'imagePath': draft.imagePath,
            if (draft.imagePaths.length > 1) 'imagePaths': draft.imagePaths,
            'supplierName': _key(draft.supplierName),
            if (draft.supplierId != null) 'supplierId': draft.supplierId,
            'supplierBranch': _key(draft.supplierBranch),
            'supplierNotes': draft.supplierNotes.trim(),
            'purchasedAt': draft.purchasedAt!.toIso8601String(),
            'hasPurchaseTime': draft.hasPurchaseTime,
            'receiptNumber': draft.receiptNumber.trim(),
            'notes': draft.notes.trim(),
            'lines': draft.lines
                .map(
                  (line) => {
                    'description': line.description.trim(),
                    'productId': line.productId,
                    if (line.sourcePage != 0) 'sourcePage': line.sourcePage,
                    'quantity': line.quantity,
                    'unit': line.unit!.name,
                    'piecesPerPack': line.piecesPerPack,
                    'grossAmountCents': line.grossAmountCents,
                    'discountCents': line.discountCents,
                  },
                )
                .toList(),
          }),
        ),
      )
      .toString();

  Future<SaveReceiptResult> _saveSnapshot(
    ReceiptDraft draft,
    String digest,
  ) async {
    final operations = await _db.query(
      'receipt_write_operations',
      where: 'operation_id = ?',
      whereArgs: [draft.operationId],
    );
    if (operations.isNotEmpty) {
      final operation = operations.single;
      if (operation['kind'] != 'confirmed_save' ||
          operation['canonical_digest'] != digest) {
        throw const ValidationException(
          'This operation ID was used for a different action or details. Use a new operation ID.',
        );
      }
      final pages =
          jsonDecode(operation['request_media_payload'] as String) as List;
      if (pages.length != draft.imagePaths.length) {
        throw const ValidationException(
          'The receipt pages changed after this save. Start a new receipt.',
        );
      }
      for (var i = 0; i < pages.length; i++) {
        final path = draft.imagePaths[i];
        if (await File(path).exists() &&
            await _files.hash(path) != pages[i]['hash']) {
          throw const ValidationException(
            'An image changed after this save. Start a new receipt instead of retrying the earlier save.',
          );
        }
      }
      return _operationResult(operation);
    }
    final prior = await _db.query(
      'receipts',
      where: 'operation_id = ?',
      whereArgs: [draft.operationId],
    );
    if (prior.isNotEmpty) {
      _validateRetry(prior.single, digest);
      final savedPages = await _db.query(
        'receipt_images',
        columns: ['image_hash'],
        where: 'receipt_id = ?',
        whereArgs: [prior.single['id']],
        orderBy: 'page_index',
      );
      if (savedPages.length != draft.imagePaths.length) {
        throw const ValidationException(
          'The receipt pages changed after this save. Start a new receipt.',
        );
      }
      for (var page = 0; page < draft.imagePaths.length; page++) {
        final path = draft.imagePaths[page];
        if (await File(path).exists() &&
            await _files.hash(path) != savedPages[page]['image_hash']) {
          throw const ValidationException(
            'An image changed after this save. Start a new receipt instead of retrying the earlier save.',
          );
        }
      }
      return _savedResult(
        _db,
        prior.single['id'] as String,
        alreadySaved: true,
      );
    }
    final copies = <StoredLocalFile>[];
    try {
      for (final path in draft.imagePaths) {
        copies.add(await _files.persist(path, category: 'receipts'));
      }
      return await _db.transaction((txn) async {
        final result = await ConfirmedReceiptWriter(
          images: copies,
          operationId: draft.operationId,
          digest: digest,
          clock: _clock,
        ).write(txn, draft);
        await _recordOperation(
          txn,
          operationId: draft.operationId,
          kind: 'confirmed_save',
          digest: digest,
          targetId: result.receiptId,
          revision: 1,
          result: result,
          media: [
            for (var i = 0; i < copies.length; i++)
              {'path': draft.imagePaths[i], 'hash': copies[i].hash},
          ],
        );
        return result;
      });
    } catch (_) {
      for (final page in copies) {
        if (page.created) await _files.remove(page.path);
      }
      rethrow;
    }
  }

  void _validateRetry(Map<String, Object?> prior, String digest) {
    if (prior['content_digest'] != digest) {
      throw const ValidationException(
        'This receipt was already saved with different details. Start a new receipt instead of changing the earlier save.',
      );
    }
  }

  Future<SaveReceiptResult> _savedResult(
    sqlite.DatabaseExecutor db,
    String receiptId, {
    required bool alreadySaved,
  }) async {
    final lines = await db.query(
      'purchase_lines',
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
      orderBy: 'sequence',
    );
    return SaveReceiptResult(
      receiptId: receiptId,
      lineIds: lines.map((row) => row['id'] as String).toList(),
      unitCostsCents: lines
          .map(
            (row) =>
                (row['net_amount_cents'] as int) / (row['total_pieces'] as int),
          )
          .toList(),
      alreadySaved: alreadySaved,
    );
  }

  @override
  Future<Map<String, LatestProductCost>> getLatestProductCosts(
    Iterable<String> productIds,
  ) async {
    final ids = productIds.toSet().toList();
    final summaries = <String, LatestProductCost>{};
    // Stay below the 999 bind-variable limit on older Android SQLite builds.
    // NOT EXISTS also avoids requiring newer SQLite window functions.
    const batchSize = 900;
    for (var start = 0; start < ids.length; start += batchSize) {
      final end = start + batchSize < ids.length
          ? start + batchSize
          : ids.length;
      final batch = ids.sublist(start, end);
      final placeholders = List.filled(batch.length, '?').join(',');
      final rows = await _db.rawQuery('''
        WITH purchases AS (
          SELECT l.product_id, l.sequence, r.recorded_order, l.net_amount_cents, l.total_pieces,
            r.supplier_id, r.purchased_at, r.purchased_date,
            r.has_purchase_time, r.created_at AS recorded_at
          FROM purchase_lines l JOIN receipts r ON r.id = l.receipt_id
          WHERE l.product_id IN ($placeholders)
        ), supplier_days AS (
          SELECT product_id, supplier_id, purchased_date,
            MIN(has_purchase_time) AS all_times_known
          FROM purchases GROUP BY product_id, supplier_id, purchased_date
        ), supplier_candidates AS (
          SELECT p.*, CASE WHEN d.all_times_known = 1
            THEN p.purchased_at ELSE '' END AS time_key
          FROM purchases p JOIN supplier_days d
            ON d.product_id = p.product_id AND d.supplier_id = p.supplier_id
            AND d.purchased_date = p.purchased_date
        ), supplier_latest AS (
          SELECT p.* FROM supplier_candidates p
          WHERE NOT EXISTS (
            SELECT 1 FROM supplier_candidates newer
            WHERE newer.product_id = p.product_id
              AND newer.supplier_id = p.supplier_id
              AND (newer.purchased_date > p.purchased_date
                OR (newer.purchased_date = p.purchased_date
                  AND (newer.time_key > p.time_key
                    OR (newer.time_key = p.time_key
                      AND (newer.recorded_order > p.recorded_order OR
                        (newer.recorded_order = p.recorded_order AND newer.sequence > p.sequence))))))
          )
        ), product_days AS (
          SELECT product_id, purchased_date,
            MIN(has_purchase_time) AS all_times_known
          FROM supplier_latest GROUP BY product_id, purchased_date
        ), product_candidates AS (
          SELECT p.product_id, p.sequence, p.recorded_order, p.net_amount_cents, p.total_pieces,
            p.purchased_at, p.purchased_date, p.recorded_at,
            CASE WHEN d.all_times_known = 1
              THEN p.purchased_at ELSE '' END AS time_key
          FROM supplier_latest p JOIN product_days d
            ON d.product_id = p.product_id
              AND d.purchased_date = p.purchased_date
        )
        SELECT p.product_id, p.net_amount_cents, p.total_pieces, p.purchased_at
        FROM product_candidates p WHERE NOT EXISTS (
          SELECT 1 FROM product_candidates newer
          WHERE newer.product_id = p.product_id
            AND (newer.purchased_date > p.purchased_date
              OR (newer.purchased_date = p.purchased_date
                AND (newer.time_key > p.time_key
                  OR (newer.time_key = p.time_key
                    AND (newer.recorded_at > p.recorded_at
                      OR (newer.recorded_at = p.recorded_at
                        AND (newer.recorded_order > p.recorded_order OR
                          (newer.recorded_order = p.recorded_order AND newer.sequence > p.sequence))))))))
        )
        ''', batch);
      for (final row in rows) {
        summaries[row['product_id'] as String] = LatestProductCost(
          costPerPieceCents:
              (row['net_amount_cents'] as int) / (row['total_pieces'] as int),
          purchasedAt: DateTime.parse(row['purchased_at'] as String),
        );
      }
    }
    return summaries;
  }

  @override
  Future<ProductComparisonData> getProductComparison(String productId) async {
    final product = await getProductById(productId);
    if (product == null) {
      throw const ValidationException('This product was not found.');
    }
    final profile = await getStoreProfile();
    final purchases = (await _db.rawQuery(
      '$purchaseSelect WHERE l.product_id = ? ORDER BY l.sequence',
      [productId],
    )).map(purchaseFromRow).toList();
    return PricingService.comparison(product, profile, purchases);
  }

  @override
  Future<RestockEstimate> calculateRestock({
    required String productId,
    required int targetPieces,
    required double additionalCost,
    Map<String, int> additionalCostsCents = const {},
  }) async {
    PricingService.validateQuantity(targetPieces);
    if (!additionalCost.isFinite ||
        additionalCost < 0 ||
        additionalCost > maxAmountCents / 100) {
      throw const ValidationException(
        'Enter a valid non-negative additional cost in pesos.',
      );
    }
    for (final extra in additionalCostsCents.values) {
      PricingService.validateMoney(extra);
    }
    final comparison = await getProductComparison(productId);
    final estimates = comparison.latestPrices
        .map(
          (row) => PricingService.estimatePurchase(
            row.purchase,
            targetPieces,
            additionalCostCents:
                additionalCostsCents[row.purchase.supplier.id] ??
                (additionalCost * 100).round(),
          ),
        )
        .toList();
    estimates.sort((a, b) => a.totalCents.compareTo(b.totalCents));
    return RestockEstimate(
      product: comparison.product,
      targetPieces: targetPieces,
      suppliers: estimates,
    );
  }

  @override
  Future<ProfitCalculation> calculateProfit({
    required String productId,
    required double costPerPiece,
    double? customMarkupPercentage,
    double? customSellingPrice,
  }) async {
    final costCents = costPerPiece * 100.0;
    final markup = customMarkupPercentage ?? 15.0;
    final sellingCents = customSellingPrice != null
        ? (customSellingPrice * 100.0).round()
        : PricingService.suggestedSellingPriceCents(costCents, markup);
    return PricingService.profit(costCents, sellingCents);
  }

  @override
  Future<BasketEstimate> calculateBasket(
    Map<String, int> targetPieces, {
    Map<String, int> additionalCostsCents = const {},
  }) async {
    final quantities = Map<String, int>.of(targetPieces);
    final extras = Map<String, int>.of(additionalCostsCents);
    final estimates = <Product, RestockEstimate>{};
    for (final entry in quantities.entries) {
      final estimate = await calculateRestock(
        productId: entry.key,
        targetPieces: entry.value,
        additionalCost: 0,
      );
      if (estimate.product != null) {
        estimates[estimate.product!] = estimate;
      }
    }
    return PricingService.basket(
      estimates,
      additionalCostsCents: extras,
      knownSuppliers: await getSuppliers(),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _pendingWrites;
    try {
      await _ocr.close();
    } finally {
      await _db.close();
    }
  }
}
