import '../services/receipt_product_match.dart';
import 'dart:math';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../services/receipt_validator.dart';
import '../services/latest_product_cost_service.dart';
import '../services/pricing_service.dart';
import '../services/ocr_engine_registry.dart';
import '../services/receipt_snapshot_codec.dart';
import '../database/pending_receipt_repository.dart';
import 'i_reseebo_data_adapter.dart';

/// In-memory mock adapter pre-loaded with realistic sari-sari store fixtures.
/// Enables immediate, offline frontend prototyping and lightweight Web testing.
class MockReseeboDataAdapter implements IReseeboDataAdapter {
  final Map<String, PendingReceipt> _pendingReceipts = {};
  final Map<String, ({String payload, PendingSaveResult result})>
  _pendingOperations = {};
  final ReceiptSnapshotCodec _pendingCodec = ReceiptSnapshotCodec();
  // Ledger search retains the confirmed evidence even while a correction is
  // pending. Product names are resolved from the current local catalog.
  final Map<String, ReceiptDraft> _confirmedLedgerEvidence = {};
  final Set<String> _reviewEvidenceReceipts = {};
  final Map<String, int> _confirmedRevisions = {};
  final Map<String, List<ReceiptRevision>> _revisionHistory = {};
  final Map<String, ({String command, SaveReceiptResult result})>
  _confirmationOperations = {};
  final Map<String, ({String command, SaveReceiptResult result})>
  _consumedPending = {};
  final Map<String, ({String payload, SaveReceiptResult result})>
  _confirmedOperations = {};
  final Map<String, String> _ledgerLinks = {};
  final Map<String, int> _receiptOrders = {};
  final Map<String, int> _lineSequences = {};
  int _nextLineSequence = 0;
  int _nextReceiptOrder = 100;
  Future<void> _receiptWrites = Future.value();

  /// All receipt writes share submission order. Revision and command checks run
  /// inside this queue; callers freeze editable input before enqueueing it.
  Future<T> _writeReceipt<T>(Future<T> Function() operation) {
    final result = _receiptWrites.then((_) => operation());
    _receiptWrites = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  static SaveReceiptResult _frozenResult(SaveReceiptResult r) =>
      SaveReceiptResult(
        receiptId: r.receiptId,
        lineIds: List.unmodifiable(r.lineIds),
        unitCostsCents: List.unmodifiable(r.unitCostsCents),
      );

  static SaveReceiptResult _retryResult(SaveReceiptResult r) =>
      SaveReceiptResult(
        receiptId: r.receiptId,
        lineIds: List.of(r.lineIds),
        unitCostsCents: List.of(r.unitCostsCents),
        alreadySaved: true,
      );

  static bool _numberMatches(
    ReceiptDraft draft,
    String name,
    String branch,
    String number,
  ) =>
      PendingReceiptRepository.key(draft.supplierName).isNotEmpty &&
      PendingReceiptRepository.key(draft.receiptNumber).isNotEmpty &&
      PendingReceiptRepository.key(draft.supplierName) ==
          PendingReceiptRepository.key(name) &&
      PendingReceiptRepository.key(draft.supplierBranch) ==
          PendingReceiptRepository.key(branch) &&
      PendingReceiptRepository.key(draft.receiptNumber) ==
          PendingReceiptRepository.key(number);

  List<String> _pendingDuplicateIds(
    ReceiptDraft draft, {
    String? excludingPendingId,
  }) {
    if (draft.allowDuplicate) return [];
    final ids = <String>[];
    for (final p in _pendingReceipts.values) {
      final previous = p.draft;
      if (p.id != excludingPendingId &&
          (previous.imagePaths.any(draft.imagePaths.contains) ||
              previous.mediaEvidence.any(
                (m) => draft.mediaEvidence.any(
                  (d) => m.original.sha256 == d.original.sha256,
                ),
              ) ||
              _numberMatches(
                draft,
                previous.supplierName,
                previous.supplierBranch,
                previous.receiptNumber,
              ))) {
        ids.add(p.id);
      }
    }
    return ids..sort();
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
    return _writeReceipt(
      () => _savePendingSnapshot(
        snapshot,
        operationId: operationId,
        pendingId: pendingId,
        expectedRevision: expectedRevision,
        correctionOfReceiptId: correctionOfReceiptId,
        expectedConfirmedRevision: expectedConfirmedRevision,
      ),
    );
  }

  Future<PendingSaveResult> _savePendingSnapshot(
    ReceiptDraft draft, {
    required String operationId,
    String? pendingId,
    int? expectedRevision,
    String? correctionOfReceiptId,
    int? expectedConfirmedRevision,
  }) async {
    PendingReceiptRepository.validateDraft(draft);
    if (operationId.trim().isEmpty) {
      throw const ValidationException('A save operation ID is required.');
    }
    if (_confirmationOperations.containsKey(operationId) ||
        _confirmedOperations.containsKey(operationId)) {
      throw const ValidationException(
        'This operation ID was used for a different action.',
      );
    }
    final payload = jsonEncode({
      'draft': _pendingCodec.toMap(draft),
      'pendingId': pendingId,
      'expectedRevision': expectedRevision,
      'correctionOfReceiptId': correctionOfReceiptId,
      'expectedConfirmedRevision': expectedConfirmedRevision,
    });
    final operation = _pendingOperations[operationId];
    if (operation != null) {
      if (operation.payload != payload) {
        throw const ValidationException(
          'This save operation already has different details. Use a new operation ID for edits.',
        );
      }
      return PendingSaveResult(
        id: operation.result.id,
        revision: operation.result.revision,
        alreadySaved: true,
      );
    }
    final prior = _pendingReceipts[pendingId];
    if (pendingId == null && expectedRevision != null) {
      throw const ValidationException(
        'A new pending receipt cannot have an expected revision.',
      );
    }
    if (pendingId != null &&
        (prior == null || expectedRevision != prior.revision)) {
      throw const RevisionConflictException();
    }
    if (prior != null &&
        (correctionOfReceiptId != null &&
                correctionOfReceiptId != prior.correctionOfReceiptId ||
            expectedConfirmedRevision != null &&
                expectedConfirmedRevision != prior.baseConfirmedRevision)) {
      throw const RevisionConflictException();
    }
    final source = correctionOfReceiptId ?? prior?.correctionOfReceiptId;
    final base = expectedConfirmedRevision ?? prior?.baseConfirmedRevision;
    if ((source == null) != (base == null)) {
      throw const ValidationException(
        'A correction requires its confirmed receipt and revision.',
      );
    }
    if (source != null &&
        (base != (_confirmedRevisions[source] ?? 1) ||
            !_receipts.any((r) => r.id == source) ||
            _pendingReceipts.values.any(
              (p) => p.id != pendingId && p.correctionOfReceiptId == source,
            ))) {
      throw const RevisionConflictException();
    }
    if (!draft.allowDuplicate) {
      final ids = <String>[];
      for (final r in _receipts) {
        if (r.id != source &&
            (r.imagePaths.any(draft.imagePaths.contains) ||
                _numberMatches(
                  draft,
                  r.supplier.name,
                  r.supplier.branch,
                  r.receiptNumber,
                ))) {
          ids.add(r.id);
        }
      }
      ids.addAll(_pendingDuplicateIds(draft, excludingPendingId: pendingId));
      if (ids.isNotEmpty) {
        ids.sort();
        throw DuplicateReceiptException(ids);
      }
    }
    final id = pendingId ?? const Uuid().v4();
    final now = DateTime.now().toUtc();
    final result = PendingSaveResult(
      id: id,
      revision: (prior?.revision ?? 0) + 1,
    );
    _pendingReceipts[id] = PendingReceipt(
      id: id,
      revision: result.revision,
      createdAt: prior?.createdAt ?? now,
      updatedAt: now,
      draft: draft,
      correctionOfReceiptId: source,
      baseConfirmedRevision: base,
    );
    _pendingOperations[operationId] = (payload: payload, result: result);
    if (source != null) _ledgerLinks[id] = source;
    return result;
  }

  @override
  Future<PendingReceipt> getPendingReceipt(String id) async {
    final pending = _pendingReceipts[id];
    if (pending == null) {
      throw const ValidationException('This pending receipt was not found.');
    }
    return pending;
  }

  @override
  Future<String?> resolveConfirmedReceiptId(String pendingId) async =>
      _ledgerLinks[pendingId];

  @override
  Future<ConfirmedReceiptEdit> getConfirmedReceiptEdit(String receiptId) async {
    final stored = _confirmedLedgerEvidence[receiptId];
    if (stored != null && _reviewEvidenceReceipts.contains(receiptId)) {
      return ConfirmedReceiptEdit(
        receiptId: receiptId,
        revision: _confirmedRevisions[receiptId] ?? 1,
        draft: stored,
      );
    }
    final detail = await getReceipt(receiptId);
    final r = detail.receipt;
    return ConfirmedReceiptEdit(
      receiptId: receiptId,
      revision: 1,
      draft: ReceiptDraft(
        imagePath: r.imagePath,
        imagePaths: r.imagePaths,
        supplierId: r.supplier.id,
        supplierName: r.supplier.name,
        supplierBranch: r.supplier.branch,
        supplierNotes: r.supplier.notes,
        purchasedAt: r.purchasedAt,
        hasPurchaseTime: r.hasPurchaseTime,
        dateConfirmed: true,
        receiptNumber: r.receiptNumber,
        notes: r.notes,
        lines: detail.lines
            .map(
              (l) => ParsedLineItem(
                id: l.id,
                productId: l.productId,
                description: l.originalDescription,
                quantity: l.quantity,
                unit: l.unit,
                piecesPerPack: l.piecesPerPack,
                grossAmountCents: l.netAmountCents,
                normalizedDiscountCents: l.discountCents,
                sourcePage: l.sourcePage,
                confirmed: true,
              ),
            )
            .toList(),
      ),
    );
  }

  @override
  Future<List<ReceiptRevision>> getReceiptRevisions(String receiptId) async {
    if (!_receipts.any((r) => r.id == receiptId)) {
      throw const ValidationException('This receipt was not found.');
    }
    return List<ReceiptRevision>.of(
      _revisionHistory[receiptId] ?? const <ReceiptRevision>[],
    ).reversed.toList();
  }

  @override
  Future<SaveReceiptResult> confirmPendingReceipt(
    String id, {
    required int expectedRevision,
    required String operationId,
  }) {
    return _writeReceipt(
      () => _confirmPending(
        id,
        expectedRevision: expectedRevision,
        operationId: operationId,
      ),
    );
  }

  Future<SaveReceiptResult> _confirmPending(
    String id, {
    required int expectedRevision,
    required String operationId,
  }) async {
    if (id.trim().isEmpty ||
        operationId.trim().isEmpty ||
        expectedRevision < 1) {
      throw const ValidationException(
        'Choose a pending receipt revision and confirmation operation ID.',
      );
    }
    if (_pendingOperations.containsKey(operationId) ||
        _confirmedOperations.containsKey(operationId)) {
      throw const ValidationException(
        'This operation ID was used for a different action.',
      );
    }
    final command = jsonEncode({
      'id': id,
      'expectedRevision': expectedRevision,
    });
    final prior = _confirmationOperations[operationId];
    if (prior != null) {
      if (prior.command != command) {
        throw const ValidationException(
          'This confirmation operation has different details. Use a new operation ID.',
        );
      }
      return _retryResult(prior.result);
    }
    final consumed = _consumedPending[id];
    if (consumed != null) {
      if (consumed.command != command) throw const RevisionConflictException();
      _confirmationOperations[operationId] = consumed;
      return _retryResult(consumed.result);
    }
    final pending = await getPendingReceipt(id);
    if (pending.revision != expectedRevision) {
      throw const RevisionConflictException();
    }
    final source = pending.correctionOfReceiptId;
    ConfirmedReceiptEdit? old;
    if (source != null) {
      old = await getConfirmedReceiptEdit(source);
      if (old.revision != pending.baseConfirmedRevision) {
        throw const RevisionConflictException();
      }
    }
    final draft = pending.draft;
    ReceiptValidator.validate(draft);
    _checkMockDuplicates(draft, pendingId: id, source: source);
    final result = _writeConfirmedDraft(
      draft,
      replacingReceiptId: source,
      existingLineIds: old?.draft.lines.map((l) => l.id).toSet(),
      recordedAt: source == null ? pending.createdAt : null,
    );
    if (old != null) {
      _revisionHistory
          .putIfAbsent(source!, () => [])
          .add(
            ReceiptRevision(
              revision: old.revision,
              recordedAt: DateTime.now().toUtc(),
              draft: old.draft,
            ),
          );
    }
    _confirmedRevisions[result.receiptId] = (old?.revision ?? 0) + 1;
    _reviewEvidenceReceipts.add(result.receiptId);
    _ledgerLinks[id] = result.receiptId;
    final record = (command: command, result: _frozenResult(result));
    _consumedPending[id] = record;
    _confirmationOperations[operationId] = record;
    _pendingReceipts.remove(id);
    return result;
  }

  void _checkMockDuplicates(
    ReceiptDraft draft, {
    String? pendingId,
    String? source,
  }) {
    if (draft.allowDuplicate) return;
    final ids = _pendingDuplicateIds(draft, excludingPendingId: pendingId);
    for (final r in _receipts) {
      if (r.id != source &&
          (r.imagePaths.any(draft.imagePaths.contains) ||
              _numberMatches(
                draft,
                r.supplier.name,
                r.supplier.branch,
                r.receiptNumber,
              ))) {
        ids.add(r.id);
      }
    }
    if (ids.isNotEmpty) throw DuplicateReceiptException(ids..sort());
  }

  @override
  Future<List<LedgerEntry>> getLedgerEntries({
    int limit = 200,
    String? query,
  }) async {
    if (limit < 1 || limit > 1000) {
      throw const ValidationException(
        'Choose a receipt limit between 1 and 1,000.',
      );
    }
    final needle = query?.trim().toLowerCase() ?? '';
    final entries = <LedgerEntry>[];
    final fixtureHistory = _products.isEmpty
        ? <PurchaseRecord>[]
        : (await getProductComparison(
            _products.first.id,
          )).history.map((h) => h.purchase).toList();
    for (final r in _receipts) {
      final correction = _pendingReceipts.values
          .where((p) => p.correctionOfReceiptId == r.id)
          .firstOrNull;
      final draft = correction?.draft;
      final search =
          '${_confirmedLedgerSearch(r, fixtureHistory)} ${draft == null ? '' : PendingReceiptRepository.searchText(draft)}';
      if (!search.toLowerCase().contains(needle)) continue;
      entries.add(
        LedgerEntry(
          id: r.id,
          status: correction == null
              ? LedgerEntryStatus.confirmed
              : LedgerEntryStatus.needsReview,
          recordedAt: r.createdAt,
          supplierDisplay: draft == null
              ? r.supplier.label
              : PendingReceiptRepository.supplierDisplay(draft),
          provisionalTotalCents: draft == null
              ? r.totalCents
              : draft.detectedTotalCents,
          confirmedReceiptId: r.id,
          pendingId: correction?.id,
        ),
      );
    }
    for (final p in _pendingReceipts.values.where(
      (p) => p.correctionOfReceiptId == null,
    )) {
      final draft = p.draft;
      if (!PendingReceiptRepository.searchText(
        draft,
      ).toLowerCase().contains(needle)) {
        continue;
      }
      entries.add(
        LedgerEntry(
          id: p.id,
          status: LedgerEntryStatus.needsReview,
          recordedAt: p.createdAt,
          supplierDisplay: PendingReceiptRepository.supplierDisplay(draft),
          provisionalTotalCents: draft.detectedTotalCents,
          pendingId: p.id,
        ),
      );
    }
    entries.sort((a, b) {
      final time = b.recordedAt.compareTo(a.recordedAt);
      return time != 0 ? time : a.id.compareTo(b.id);
    });
    return entries.take(limit).toList();
  }

  String _confirmedLedgerSearch(
    Receipt receipt,
    List<PurchaseRecord> fixtureHistory,
  ) {
    String productName(String? id) =>
        _products.where((p) => p.id == id).firstOrNull?.name ?? '';
    final evidence = _confirmedLedgerEvidence[receipt.id];
    final lineEvidence = evidence == null
        ? fixtureHistory
              .where((p) => p.receiptId == receipt.id)
              .map(
                (p) => '${p.originalDescription} ${productName(p.productId)}',
              )
        : evidence.lines.map(
            (l) => '${l.description} ${productName(l.productId)}',
          );
    return [
      receipt.supplier.name,
      receipt.supplier.branch,
      receipt.receiptNumber,
      receipt.notes,
      evidence?.rawText ?? '',
      ...lineEvidence,
    ].join(' ');
  }

  @override
  Future<List<OcrEngineDescriptor>> getOcrEngines() async => const [
    OcrEngineRegistry.mlKitDescriptor,
  ];
  @override
  Future<void> releaseOcrSession() async {}

  final Set<String> _categories = {};
  @override
  Future<List<String>> getProductCategories() async {
    final values = <String, String>{};
    for (final name in [..._categories, ..._products.map((p) => p.category)]) {
      if (name.trim().isNotEmpty) {
        values.putIfAbsent(name.trim().toLowerCase(), () => name.trim());
      }
    }
    return values.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  @override
  Future<void> addProductCategory(String name) async {
    if (name.trim().isEmpty) {
      throw const ValidationException('Enter a category name.');
    }
    if (!(await getProductCategories()).any(
      (value) => value.toLowerCase() == name.trim().toLowerCase(),
    )) {
      _categories.add(name.trim());
    }
  }

  @override
  Future<void> removeProductCategory(String name) async {
    final key = name.trim().toLowerCase();
    _categories.removeWhere((value) => value.toLowerCase() == key);
    for (var index = 0; index < _products.length; index++) {
      if (_products[index].category.trim().toLowerCase() == key) {
        _products[index] = _products[index].copyWith(category: '');
      }
    }
  }

  StoreProfile _profile = const StoreProfile(
    name: "Aling Nena's Sari-Sari Store",
    ownerName: 'Elena Santos',
    defaultMarkupPercent: 20.0,
  );

  final List<Supplier> _suppliers = [
    const Supplier(
      id: 'sup_a',
      name: 'Puregold Price Club',
      branch: 'Branch A - San Juan',
      notes: 'Near public market',
    ),
    const Supplier(
      id: 'sup_b',
      name: 'Supermarket B (Megamart)',
      branch: 'Highway Branch',
      notes: 'Wholesale packs available',
    ),
    const Supplier(
      id: 'sup_c',
      name: 'Wholesaler C',
      branch: 'Town Proper',
      notes: 'Cash only, discounts on 5+ boxes',
    ),
  ];

  final List<Product> _products = [
    const Product(
      id: 'prod_coffee_26g',
      name: 'Brand X Original Coffee 26g',
      brand: 'Brand X',
      variant: 'Original Coffee',
      size: '26g',
      category: 'Beverages',
      barcode: '4800016622114',
      markupPercent: null, // Uses store default (20%)
      sellingPriceCents: 1000,
    ),
    const Product(
      id: 'prod_milk_33g',
      name: 'Bear Brand Fortified Milk 33g',
      brand: 'Bear Brand',
      variant: 'Fortified Powdered Milk',
      size: '33g',
      category: 'Dairy',
      barcode: '4800361280312',
      markupPercent: 25.0,
      sellingPriceCents: 1600,
    ),
    const Product(
      id: 'prod_soysauce_385ml',
      name: 'Silver Swan Soy Sauce 385ml',
      brand: 'Silver Swan',
      variant: 'Soy Sauce Bottle',
      size: '385ml',
      category: 'Condiments',
      barcode: '4801011100344',
      markupPercent: 15.0,
      sellingPriceCents: 2200,
    ),
    const Product(
      id: 'prod_pancit_60g',
      name: 'Lucky Me! Pancit Canton 60g',
      brand: 'Lucky Me!',
      variant: 'Original Flavor',
      size: '60g',
      category: 'Instant Noodles',
      barcode: '4807770270014',
      markupPercent: null,
      sellingPriceCents: 1500,
    ),
  ];

  late final List<Receipt> _receipts;

  MockReseeboDataAdapter() {
    _receipts = [
      Receipt(
        id: 'rec_001',
        supplier: _suppliers[0],
        purchasedAt: DateTime(2026, 10, 8),
        hasPurchaseTime: false,
        createdAt: DateTime(2026, 10, 8, 14, 30),
        imagePath: 'assets/placeholders/sample_receipt_1.png',
        receiptNumber: 'OR-89211',
        totalCents: 16800,
        lineCount: 1,
      ),
      Receipt(
        id: 'rec_002',
        supplier: _suppliers[2],
        purchasedAt: DateTime(2026, 10, 7),
        hasPurchaseTime: false,
        createdAt: DateTime(2026, 10, 7, 10, 15),
        imagePath: 'assets/placeholders/sample_receipt_2.png',
        receiptNumber: 'SI-44120',
        totalCents: 24500,
        lineCount: 2,
      ),
      Receipt(
        id: 'rec_003',
        supplier: _suppliers[1],
        purchasedAt: DateTime(2026, 10, 5),
        hasPurchaseTime: false,
        createdAt: DateTime(2026, 10, 5, 16, 45),
        imagePath: 'assets/placeholders/sample_receipt_3.png',
        receiptNumber: 'INV-1092',
        totalCents: 7800,
        lineCount: 1,
      ),
      Receipt(
        id: 'rec_004',
        supplier: _suppliers[0],
        purchasedAt: DateTime(2026, 10, 1),
        hasPurchaseTime: false,
        createdAt: DateTime(2026, 10, 1, 9, 0),
        imagePath: 'assets/placeholders/sample_receipt_4.png',
        receiptNumber: 'OR-81102',
        totalCents: 8000,
        lineCount: 1,
      ),
    ];
  }

  @override
  Future<StoreProfile> getStoreProfile() async => _profile;

  @override
  Future<void> updateStoreProfile(StoreProfile profile) async {
    _profile = profile;
  }

  @override
  Future<List<Product>> getProducts({String? query}) async {
    if (query == null || query.trim().isEmpty) {
      return List.unmodifiable(_products);
    }
    final q = query.toLowerCase();
    return _products.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.brand.toLowerCase().contains(q) ||
          p.variant.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Future<Product?> getProductById(String id) async {
    return _products.where((p) => p.id == id).firstOrNull;
  }

  @override
  Future<void> saveProduct(Product product) async {
    final index = _products.indexWhere((p) => p.id == product.id);
    if (index >= 0) {
      _products[index] = product;
    } else {
      _products.add(product);
    }
  }

  @override
  Future<List<ProductMatchSuggestion>> matchAliases(
    String rawOcrDescription, {
    String? supplierId,
  }) async {
    return receiptProductSuggestions(rawOcrDescription, _products);
  }

  @override
  Future<List<ProductAlias>> getAliases(String productId) async => [];

  @override
  Future<void> deleteAlias(String aliasId) async {}

  @override
  Future<List<Supplier>> getSuppliers() async {
    return List.unmodifiable(_suppliers);
  }

  @override
  Future<Supplier?> getSupplierById(String id) async {
    return _suppliers.where((s) => s.id == id).firstOrNull;
  }

  @override
  Future<void> saveSupplier(Supplier supplier) async {
    final index = _suppliers.indexWhere((s) => s.id == supplier.id);
    if (index >= 0) {
      _suppliers[index] = supplier;
    } else {
      _suppliers.add(supplier);
    }
  }

  @override
  Future<List<Receipt>> getRecentReceipts({
    int limit = 200,
    String? query,
  }) async {
    var sorted = List<Receipt>.from(_receipts)
      ..sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));
    if (query != null && query.isNotEmpty) {
      sorted = sorted
          .where(
            (r) => r.supplierName.toLowerCase().contains(query.toLowerCase()),
          )
          .toList();
    }
    return sorted.take(limit).toList();
  }

  @override
  Future<ReceiptDetail> getReceipt(String receiptId) async {
    final r = _receipts.where((x) => x.id == receiptId).firstOrNull;
    if (r == null) {
      throw const ValidationException('This receipt was not found.');
    }
    final lines = _confirmedLedgerEvidence.containsKey(receiptId)
        ? _storedPurchases(receiptId)
        : (await _fixtureProductComparison(_products.first.id)).history
              .map((h) => h.purchase)
              .where((p) => p.receiptId == receiptId)
              .toList();
    return ReceiptDetail(receipt: r, lines: lines);
  }

  @override
  Future<ReceiptDraft> processReceiptImage(
    String localImagePath, {
    String? recognitionImagePath,
    String? comparisonImagePath,
    OcrEngineId engineId = OcrEngineId.mlKit,
  }) async {
    return ReceiptDraft(
      imagePath: localImagePath,
      supplierId: 'sup_a',
      supplierName: 'Puregold Price Club',
      supplierBranch: 'Branch A - San Juan',
      purchasedAt: DateTime(2026, 10, 8),
      receiptNumber: 'OR-${Random().nextInt(90000) + 10000}',
      detectedTotalCents: 32400,
      lines: [
        ParsedLineItem(
          id: 'line_1',
          description: 'BRANDX COF ORIG 26G',
          productId: 'prod_coffee_26g',
          quantity: 2,
          unit: PurchaseUnit.pack,
          piecesPerPack: 10,
          grossAmountCents: 16800,
          discountCents: 0,
          confirmed: true,
        ),
        ParsedLineItem(
          id: 'line_2',
          description: 'BEAR BRND PWDR 33G',
          productId: 'prod_milk_33g',
          quantity: 1,
          unit: PurchaseUnit.pack,
          piecesPerPack: 12,
          grossAmountCents: 15600,
          discountCents: 0,
          confirmed: false,
        ),
      ],
    );
  }

  @override
  Future<SaveReceiptResult> saveConfirmedReceipt(ReceiptDraft confirmedDraft) {
    final draft = confirmedDraft.snapshot();
    return _writeReceipt(() => _saveConfirmedSnapshot(draft));
  }

  Future<SaveReceiptResult> _saveConfirmedSnapshot(ReceiptDraft draft) async {
    ReceiptValidator.validate(draft);
    if (_pendingOperations.containsKey(draft.operationId) ||
        _confirmationOperations.containsKey(draft.operationId)) {
      throw const ValidationException(
        'This operation ID was used for a different action.',
      );
    }
    final payload = _pendingCodec.encode(draft);
    final prior = _confirmedOperations[draft.operationId];
    if (prior != null) {
      if (prior.payload != payload) {
        throw const ValidationException(
          'This save operation has different details. Use a new operation ID.',
        );
      }
      return _retryResult(prior.result);
    }
    _checkMockDuplicates(draft);
    final result = _writeConfirmedDraft(draft);
    _confirmedOperations[draft.operationId] = (
      payload: payload,
      result: _frozenResult(result),
    );
    _confirmedRevisions[result.receiptId] = 1;
    return result;
  }

  SaveReceiptResult _writeConfirmedDraft(
    ReceiptDraft input, {
    String? replacingReceiptId,
    DateTime? recordedAt,
    Set<String>? existingLineIds,
  }) {
    final draft = input.snapshot();
    for (final id in draft.lines.map((l) => l.productId).whereType<String>()) {
      if (!_products.any((p) => p.id == id)) {
        throw const ValidationException('A selected product no longer exists.');
      }
    }
    final supplierKey = PendingReceiptRepository.key(draft.supplierName);
    final branchKey = PendingReceiptRepository.key(draft.supplierBranch);
    Supplier? supplier = _suppliers
        .where(
          (s) => draft.supplierId == null
              ? PendingReceiptRepository.key(s.name) == supplierKey &&
                    PendingReceiptRepository.key(s.branch) == branchKey
              : s.id == draft.supplierId,
        )
        .firstOrNull;
    if (draft.supplierId != null &&
        (supplier == null ||
            PendingReceiptRepository.key(supplier.name) != supplierKey ||
            PendingReceiptRepository.key(supplier.branch) != branchKey)) {
      throw const ValidationException(
        'The selected supplier changed. Choose its branch again.',
      );
    }
    if (supplier == null) {
      supplier = Supplier(
        id: const Uuid().v4(),
        name: draft.supplierName.trim(),
        branch: draft.supplierBranch.trim(),
        notes: draft.supplierNotes.trim(),
      );
      _suppliers.add(supplier);
    }
    final receiptId = replacingReceiptId ?? const Uuid().v4();
    final old = replacingReceiptId == null
        ? null
        : _receipts.where((r) => r.id == replacingReceiptId).firstOrNull;
    final oldIds =
        _confirmedLedgerEvidence[receiptId]?.lines.map((l) => l.id).toSet() ??
        existingLineIds ??
        <String>{};
    final payload = _pendingCodec.toMap(draft);
    final data = payload['draft'] as Map<String, Object?>;
    final lines = data['lines'] as List<Map<String, Object?>>;
    final imported = <String, String>{};
    final lineIds = <String>[];
    final costs = <double>[];
    for (var i = 0; i < draft.lines.length; i++) {
      final line = draft.lines[i];
      var productId = line.productId;
      if (productId == null) {
        final key = PendingReceiptRepository.key(line.description);
        productId = imported[key];
        if (productId == null) {
          productId = const Uuid().v4();
          imported[key] = productId;
          _products.add(
            Product(
              id: productId,
              name: line.description.trim(),
              brand: '',
              variant: '',
              size: '',
              nameOnly: true,
            ),
          );
        }
      }
      final lineId = oldIds.contains(line.id) ? line.id : const Uuid().v4();
      _lineSequences.putIfAbsent(lineId, () => ++_nextLineSequence);
      lines[i]['id'] = lineId;
      lines[i]['productId'] = productId;
      lineIds.add(lineId);
      costs.add(line.netAmountCents! / line.totalPieces!);
    }
    data['supplierId'] = supplier.id;
    final evidence = _pendingCodec.fromMap(payload);
    _confirmedLedgerEvidence[receiptId] = evidence;
    _receiptOrders.putIfAbsent(receiptId, () => ++_nextReceiptOrder);
    final receipt = Receipt(
      id: receiptId,
      supplier: supplier,
      purchasedAt: draft.purchasedAt!,
      hasPurchaseTime: draft.hasPurchaseTime,
      createdAt: old?.createdAt ?? recordedAt ?? DateTime.now().toUtc(),
      imagePath: draft.imagePath,
      imagePaths: draft.imagePaths,
      receiptNumber: draft.receiptNumber,
      notes: draft.notes,
      totalCents: draft.lines.fold<int>(0, (sum, l) => sum + l.netAmountCents!),
      lineCount: draft.lines.length,
    );
    if (old == null) {
      _receipts.insert(0, receipt);
    } else {
      _receipts[_receipts.indexOf(old)] = receipt;
    }
    return SaveReceiptResult(
      receiptId: receiptId,
      lineIds: lineIds,
      unitCostsCents: costs,
    );
  }

  List<PurchaseRecord> _storedPurchases(String receiptId) {
    final draft = _confirmedLedgerEvidence[receiptId];
    if (draft == null) return [];
    final receipt = _receipts.firstWhere((r) => r.id == receiptId);
    return draft.lines
        .map(
          (l) => PurchaseRecord(
            id: l.id,
            receiptId: receiptId,
            productId: l.productId!,
            supplier: receipt.supplier,
            purchasedAt: receipt.purchasedAt,
            hasPurchaseTime: receipt.hasPurchaseTime,
            recordedAt: receipt.createdAt,
            originalDescription: l.description,
            quantity: l.quantity!,
            unit: l.unit!,
            piecesPerPack: l.piecesPerPack!,
            netAmountCents: l.netAmountCents!,
            discountCents: l.discountCents,
            imagePath: draft.imagePaths[l.sourcePage],
            receiptNumber: draft.receiptNumber,
            sequence: _lineSequences[l.id] ?? 0,
            recordedOrder: _receiptOrders[receiptId] ?? 0,
            sourcePage: l.sourcePage,
          ),
        )
        .toList();
  }

  @override
  Future<ProductComparisonData> getProductComparison(String productId) async {
    final product = await getProductById(productId);
    if (product == null) {
      throw const ValidationException('This product was not found.');
    }
    final fixture = productId.startsWith('prod_')
        ? await _fixtureProductComparison(productId)
        : null;
    final history = <PurchaseRecord>[
      if (fixture != null)
        ...fixture.history
            .map((h) => h.purchase)
            .where((p) => !_confirmedLedgerEvidence.containsKey(p.receiptId)),
      for (final id in _confirmedLedgerEvidence.keys)
        ..._storedPurchases(id).where((p) => p.productId == productId),
    ];
    return PricingService.comparison(product, _profile, history);
  }

  Future<ProductComparisonData> _fixtureProductComparison(
    String productId,
  ) async {
    final product = await getProductById(productId) ?? _products.first;

    final pPuregold = PurchaseRecord(
      id: 'pur_1',
      receiptId: 'rec_001',
      productId: product.id,
      supplier: _suppliers[0],
      purchasedAt: DateTime(2026, 10, 8),
      hasPurchaseTime: false,
      recordedAt: DateTime(2026, 10, 8),
      originalDescription: 'Brand X Coffee 26g 10s',
      quantity: 2,
      unit: PurchaseUnit.pack,
      piecesPerPack: 10,
      netAmountCents: 16800,
      imagePath: 'assets/placeholders/sample_receipt_1.png',
    );

    final pMegamart = PurchaseRecord(
      id: 'pur_2',
      receiptId: 'rec_003',
      productId: product.id,
      supplier: _suppliers[1],
      purchasedAt: DateTime(2026, 10, 5),
      hasPurchaseTime: false,
      recordedAt: DateTime(2026, 10, 5),
      originalDescription: 'Brand X Coffee 26g Pack of 10',
      quantity: 1,
      unit: PurchaseUnit.pack,
      piecesPerPack: 10,
      netAmountCents: 8700,
      imagePath: 'assets/placeholders/sample_receipt_3.png',
    );

    final pWholesaler = PurchaseRecord(
      id: 'pur_3',
      receiptId: 'rec_002',
      productId: product.id,
      supplier: _suppliers[2],
      purchasedAt: DateTime(2026, 10, 7),
      hasPurchaseTime: false,
      recordedAt: DateTime(2026, 10, 7),
      originalDescription: 'Brand X 26g Box',
      quantity: 1,
      unit: PurchaseUnit.pack,
      piecesPerPack: 10,
      netAmountCents: 8200,
      imagePath: 'assets/placeholders/sample_receipt_2.png',
    );

    final pHistoricalOld = PurchaseRecord(
      id: 'pur_4',
      receiptId: 'rec_004',
      productId: product.id,
      supplier: _suppliers[0],
      purchasedAt: DateTime(2026, 10, 1),
      hasPurchaseTime: false,
      recordedAt: DateTime(2026, 10, 1),
      originalDescription: 'Brand X Coffee 26g Promo',
      quantity: 1,
      unit: PurchaseUnit.pack,
      piecesPerPack: 10,
      netAmountCents: 8000,
      imagePath: 'assets/placeholders/sample_receipt_4.png',
    );

    return ProductComparisonData(
      product: product,
      profile: _profile,
      latestPrices: [
        SupplierPriceRow(purchase: pWholesaler, bestCostPerPieceCents: 820.0),
        SupplierPriceRow(purchase: pPuregold, bestCostPerPieceCents: 820.0),
        SupplierPriceRow(purchase: pMegamart, bestCostPerPieceCents: 820.0),
      ],
      history: [
        PriceHistoryRecord(
          purchase: pPuregold,
          previousCostPerPieceCents: 800.0,
        ),
        PriceHistoryRecord(
          purchase: pWholesaler,
          previousCostPerPieceCents: null,
        ),
        PriceHistoryRecord(
          purchase: pMegamart,
          previousCostPerPieceCents: null,
        ),
        PriceHistoryRecord(
          purchase: pHistoricalOld,
          previousCostPerPieceCents: null,
        ),
      ],
      lowestHistorical: pHistoricalOld,
    );
  }

  @override
  Future<RestockEstimate> calculateRestock({
    required String productId,
    required int targetPieces,
    required double additionalCost,
    Map<String, int> additionalCostsCents = const {},
  }) async {
    final comparison = await getProductComparison(productId);
    final additionalCents = (additionalCost * 100).round();

    final estimates = comparison.latestPrices.map((row) {
      return PricingService.estimatePurchase(
        row.purchase,
        targetPieces,
        additionalCostCents:
            additionalCostsCents[row.purchase.supplier.id] ?? additionalCents,
      );
    }).toList();

    return RestockEstimate(
      targetPieces: targetPieces,
      additionalCostCents: additionalCents,
      estimates: estimates,
    );
  }

  @override
  Future<Map<String, LatestProductCost>> getLatestProductCosts(
    Iterable<String> productIds,
  ) async {
    final summaries = <String, LatestProductCost>{};
    for (final id in productIds.toSet()) {
      final comparison = await getProductComparison(id);
      final cost = latestProductCost(
        comparison.latestPrices.map((row) => row.purchase).toList(),
      );
      if (cost != null) summaries[id] = cost;
    }
    return summaries;
  }

  @override
  Future<ReceiptDraft> processReceiptImages(
    List<String> localImagePaths, {
    List<String>? recognitionImagePaths,
    List<String>? comparisonImagePaths,
    OcrEngineId engineId = OcrEngineId.mlKit,
    String preprocessingRevision = '1',
  }) async {
    return processReceiptImage(
      localImagePaths.first,
      recognitionImagePath: recognitionImagePaths?.firstOrNull,
      comparisonImagePath: comparisonImagePaths?.firstOrNull,
      engineId: engineId,
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
    return const BasketEstimate(
      groups: [],
      missingProducts: [],
      alternatives: [],
    );
  }

  @override
  Future<void> close() async {}
}
