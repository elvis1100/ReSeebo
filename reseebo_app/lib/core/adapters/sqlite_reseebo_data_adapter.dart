import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:uuid/uuid.dart';

import '../database/reseebo_database.dart';
import '../database/row_mappers.dart';
import '../services/local_file_store.dart';
import '../services/ocr_service.dart';
import '../services/pricing_service.dart';
import '../services/receipt_parser.dart';
import '../services/receipt_validator.dart';
import '../services/starter_catalog_service.dart';
import 'i_reseebo_data_adapter.dart';

class SqliteReseeboDataAdapter implements IReseeboDataAdapter {
  SqliteReseeboDataAdapter._(this._db, this._files, this._ocr, this._clock);
  final sqlite.Database _db;
  final LocalFileStore _files;
  final OcrService _ocr;
  final DateTime Function() _clock;
  final ReceiptParser _parser = ReceiptParser();
  Future<void> _pendingWrites = Future.value();
  bool _closed = false;

  /// Defaults open the phone's private support directory. Tests inject an FFI
  /// factory, database path, media directory and OCR double, retaining real SQL.
  static Future<SqliteReseeboDataAdapter> open({
    sqlite.DatabaseFactory? databaseFactory,
    String? databasePath,
    Directory? mediaDirectory,
    OcrService? ocrService,
    DateTime Function()? clock,
    List<Product>? starterProducts,
  }) async {
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
      ocrService ?? MlKitOcrService(),
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
  Future<void> saveProduct(Product product) => _write(() async {
    if ([
      product.id,
      product.name,
      product.brand,
      product.variant,
      product.size,
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
    if (old != null &&
        (_key(old.brand) != _key(product.brand) ||
            _key(old.variant) != _key(product.variant) ||
            _key(old.size) != _key(product.size))) {
      final history = await _db.query(
        'purchase_lines',
        columns: ['id'],
        where: 'product_id = ?',
        whereArgs: [product.id],
        limit: 1,
      );
      if (history.isNotEmpty) {
        throw const ValidationException(
          'This product has purchase history. Keep its brand, variant and size, or create a separate product for a different item.',
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
      if (old == null) {
        await _db.insert('products', {
          'id': product.id,
          ...values,
          'created_at': now,
        });
      } else {
        await _db.update(
          'products',
          values,
          where: 'id = ?',
          whereArgs: [product.id],
        );
      }
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
    String rawOcrDescription,
  ) async {
    final key = _key(rawOcrDescription);
    if (key.isEmpty) return [];
    final exact = await _db.rawQuery(
      'SELECT DISTINCT p.* FROM products p JOIN product_aliases a ON a.product_id = p.id WHERE a.description_key = ?',
      [key],
    );
    final suggestions = exact
        .map(
          (row) => ProductMatchSuggestion(
            product: productFromRow(row),
            reason: exact.length > 1
                ? 'This description has more than one confirmed mapping. Choose the exact variant and size.'
                : 'Previously confirmed receipt description. Check this purchase before confirming.',
            exactAlias: true,
          ),
        )
        .toList();
    if (suggestions.isNotEmpty) return suggestions;
    final tokens = key
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length >= 2)
        .toSet();
    if (tokens.isEmpty) return [];
    final candidates = <(Product, int)>[];
    for (final product in await getProducts()) {
      final identity = _key(
        '${product.name} ${product.brand} ${product.variant} ${product.size}',
      );
      final score = tokens.where((token) => identity.contains(token)).length;
      if (score >= (tokens.length > 1 ? 2 : 1)) {
        candidates.add((product, score));
      }
    }
    candidates.sort((a, b) => b.$2.compareTo(a.$2));
    return candidates
        .take(8)
        .map(
          (entry) => ProductMatchSuggestion(
            product: entry.$1,
            reason:
                'Similar catalog text. Confirm the exact brand, variant and size.',
          ),
        )
        .toList();
  }

  @override
  Future<List<ProductAlias>> getAliases(String productId) async =>
      (await _db.query(
            'product_aliases',
            where: 'product_id = ?',
            whereArgs: [productId],
            orderBy: 'description COLLATE NOCASE',
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
  }) => processReceiptImages(
    [localImagePath],
    recognitionImagePaths: [recognitionImagePath ?? localImagePath],
  );

  @override
  Future<ReceiptDraft> processReceiptImages(
    List<String> localImagePaths, {
    List<String>? recognitionImagePaths,
  }) async {
    final originals = List<String>.of(localImagePaths);
    final adjusted = List<String>.of(recognitionImagePaths ?? originals);
    if (originals.isEmpty ||
        originals.length > maxReceiptPages ||
        adjusted.length != originals.length) {
      throw const ValidationException(
        'Choose 1 to 20 photos in receipt order.',
      );
    }
    final hashes = <String>{};
    for (final path in originals) {
      if (!hashes.add(await _files.hash(path))) {
        throw const ValidationException(
          'The same receipt photo was added twice. Remove the repeated page.',
        );
      }
    }
    final pages = <ReceiptOcrPage>[];
    for (var index = 0; index < originals.length; index++) {
      try {
        final text = await _ocr.recognize(adjusted[index]);
        pages.add(
          ReceiptOcrPage(
            imagePath: originals[index],
            recognitionImagePath: adjusted[index] == originals[index]
                ? null
                : adjusted[index],
            textLines: text,
          ),
        );
      } on AppException catch (failure) {
        throw AppException('Photo ${index + 1}: ${failure.message}');
      }
    }
    return _parser.parsePages(pages: pages);
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
    final prior = await _db.query(
      'receipts',
      where: 'operation_id = ?',
      whereArgs: [draft.operationId],
    );
    if (prior.isNotEmpty) {
      _validateRetry(prior.first, digest);
      final savedPages = await _db.query(
        'receipt_images',
        columns: ['image_hash'],
        where: 'receipt_id = ?',
        whereArgs: [prior.first['id']],
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
      return _savedResult(_db, prior.first['id'] as String, alreadySaved: true);
    }
    final copies = <StoredLocalFile>[];
    try {
      final hashes = <String>{};
      for (final path in draft.imagePaths) {
        final page = await _files.persist(path, category: 'receipts');
        copies.add(page);
        if (!hashes.add(page.hash)) {
          throw const ValidationException(
            'The same image cannot be saved as two receipt pages.',
          );
        }
      }
      final copied = copies.first;
      final result = await _db.transaction((txn) async {
        final existing = await txn.query(
          'receipts',
          where: 'operation_id = ?',
          whereArgs: [draft.operationId],
        );
        if (existing.isNotEmpty) {
          _validateRetry(existing.first, digest);
          return _savedResult(
            txn,
            existing.first['id'] as String,
            alreadySaved: true,
          );
        }
        for (final id in draft.lines.map((line) => line.productId!).toSet()) {
          final products = await txn.query(
            'products',
            where: 'id = ?',
            whereArgs: [id],
          );
          if (products.isEmpty) {
            throw const ValidationException(
              'A selected product no longer exists. Confirm the product matches again.',
            );
          }
        }
        final now = _now;
        final suppliers = await txn.query(
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
          await txn.insert('suppliers', {
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
        final numberKey = _key(draft.receiptNumber);
        final placeholders = List.filled(copies.length, '?').join(',');
        final duplicates = await txn.rawQuery(
          "SELECT DISTINCT r.id AS id FROM receipts r JOIN receipt_images i ON i.receipt_id = r.id "
          "WHERE i.image_hash IN ($placeholders) OR (r.supplier_id = ? AND r.receipt_number_key = ? AND r.receipt_number_key != '')",
          [...copies.map((page) => page.hash), supplierId, numberKey],
        );
        if (duplicates.isNotEmpty && !draft.allowDuplicate) {
          throw DuplicateReceiptException(
            duplicates.map((row) => row['id'] as String).toList(),
          );
        }
        // Supplier notes are edited through saveSupplier; receipt imports must
        // not overwrite another branch's metadata with stale draft notes.
        final receiptId = const Uuid().v4();
        final date = draft.purchasedAt!;
        final normalizedDate = draft.hasPurchaseTime
            ? date
            : DateTime(date.year, date.month, date.day);
        final total = draft.lines.fold<int>(
          0,
          (sum, line) => sum + line.netAmountCents!,
        );
        await txn.insert('receipts', {
          'id': receiptId,
          'operation_id': draft.operationId,
          'content_digest': digest,
          'supplier_id': supplierId,
          'purchased_at': normalizedDate.toIso8601String(),
          'purchased_date':
              '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
          'purchase_time': draft.hasPurchaseTime
              ? '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}'
              : null,
          'has_purchase_time': draft.hasPurchaseTime ? 1 : 0,
          'image_path': copied.path,
          'image_hash': copied.hash,
          'receipt_number': draft.receiptNumber.trim(),
          'receipt_number_key': numberKey,
          'notes': draft.notes.trim(),
          'raw_text': draft.rawText,
          'total_cents': total,
          'created_at': now,
          'updated_at': now,
        });
        for (var page = 0; page < copies.length; page++) {
          await txn.insert('receipt_images', {
            'receipt_id': receiptId,
            'page_index': page,
            'image_path': copies[page].path,
            'image_hash': copies[page].hash,
          });
        }
        final lineIds = <String>[];
        final costs = <double>[];
        for (final line in draft.lines) {
          final lineId = const Uuid().v4();
          await txn.insert('purchase_lines', {
            'id': lineId,
            'receipt_id': receiptId,
            'product_id': line.productId,
            'source_page': line.sourcePage,
            'original_description': line.description.trim(),
            'quantity': line.quantity,
            'unit': line.unit!.name,
            'pieces_per_pack': line.piecesPerPack,
            'total_pieces': line.totalPieces,
            'gross_amount_cents': line.grossAmountCents,
            'discount_cents': line.discountCents,
            'net_amount_cents': line.netAmountCents,
            'created_at': now,
            'updated_at': now,
          });
          await txn.insert('product_aliases', {
            'id': const Uuid().v4(),
            'product_id': line.productId,
            'description': line.description.trim(),
            'description_key': _key(line.description),
            'created_at': now,
            'updated_at': now,
          }, conflictAlgorithm: sqlite.ConflictAlgorithm.ignore);
          lineIds.add(lineId);
          costs.add(line.netAmountCents! / line.totalPieces!);
        }
        return SaveReceiptResult(
          receiptId: receiptId,
          lineIds: lineIds,
          unitCostsCents: costs,
        );
      });
      if (result.alreadySaved) {
        for (final page in copies) {
          if (page.created) await _files.remove(page.path);
        }
      }
      return result;
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
          SELECT l.product_id, l.sequence, l.net_amount_cents, l.total_pieces,
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
                      AND newer.sequence > p.sequence))))
          )
        ), product_days AS (
          SELECT product_id, purchased_date,
            MIN(has_purchase_time) AS all_times_known
          FROM supplier_latest GROUP BY product_id, purchased_date
        ), product_candidates AS (
          SELECT p.product_id, p.sequence, p.net_amount_cents, p.total_pieces,
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
                        AND newer.sequence > p.sequence))))))
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
