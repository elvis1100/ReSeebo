import 'package:flutter/foundation.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/services/receipt_product_match.dart';
import '../../../core/services/receipt_purchase_datetime.dart';
import '../../../core/services/receipt_layout.dart';
import '../../../core/services/receipt_suggestion_service.dart';
import '../../../core/services/receipt_snapshot_codec.dart';
import 'pending_receipt_save_command.dart';

enum ReceiptLineField {
  description('Description'),
  quantity('Quantity'),
  piecesPerPack('Pieces per pack'),
  amount('Amount paid');

  const ReceiptLineField(this.label);
  final String label;
}

class ReceiptReviewState extends ChangeNotifier {
  ReceiptReviewState({
    required this.adapter,
    required ReceiptDraft draft,
    this.pendingId,
    this.expectedRevision,
    this.correctionOfReceiptId,
    this.expectedConfirmedRevision,
    DateTime? importedAt,
    bool? preserveSuggestions,
  }) : draft = draft.snapshot(),
       _importedAt = (importedAt ?? DateTime.now()).toLocal(),
       preserveSuggestions =
           preserveSuggestions ??
           (pendingId != null || correctionOfReceiptId != null),
       _preserveOnNextLoad =
           preserveSuggestions ??
           (pendingId != null || correctionOfReceiptId != null) {
    if (!this.preserveSuggestions) {
      for (final line in this.draft.lines) {
        _prepareLine(line);
      }
    }
    _rememberValues();
  }

  /// New reviews use the final amount paid. Retain the net amount from older
  /// drafts without exposing a second deduction; saved history is untouched.
  void _prepareLine(ParsedLineItem line) {
    final discount = line.discountCents;
    final normalized = line.normalizedDiscountCents;
    final gross = line.grossAmountCents;
    // Preserve malformed discounts for validation instead of erasing evidence.
    // A missing gross may be calculated later from retained explicit unit price.
    if (discount > 0 &&
        normalized >= 0 &&
        normalized <= maxAmountCents &&
        discount <= maxAmountCents - normalized &&
        (gross == null || (gross <= maxAmountCents && discount < gross))) {
      line.grossAmountCents = line.netAmountCents;
      line.normalizedDiscountCents += discount;
      line.discountCents = 0;
    }
    if (line.unit == null &&
        !ReceiptSuggestionService.isWeighted(line) &&
        line.provenance[ReceiptSuggestionField.unit]?.origin !=
            ReceiptFieldOrigin.ownerEdited) {
      line.unit = PurchaseUnit.piece;
      line.piecesPerPack = 1;
      line.provenance[ReceiptSuggestionField.unit] =
          const ReceiptFieldProvenance(
            origin: ReceiptFieldOrigin.assumed,
            explanation: 'Pieces assumed; confirm the purchase unit.',
          );
      line.provenance[ReceiptSuggestionField.piecesPerPack] =
          const ReceiptFieldProvenance(
            origin: ReceiptFieldOrigin.assumed,
            explanation: 'One piece per individual unit.',
          );
      line.confirmed = false;
    }
  }

  final IReseeboDataAdapter adapter;
  final ReceiptDraft draft;
  final bool preserveSuggestions;
  bool _preserveOnNextLoad;
  String? pendingId;
  int? expectedRevision;
  final String? correctionOfReceiptId;
  final int? expectedConfirmedRevision;
  PendingReceiptSaveCommand? _pendingCommand;
  List<Product> products = [];
  List<Supplier> suppliers = [];
  bool loading = true;
  bool saving = false;
  String? error;
  int selectedPage = 0;
  final DateTime _importedAt;
  final ReceiptSuggestionService _suggestions = ReceiptSuggestionService();
  final List<PurchaseRecord> _confirmedHistory = [];
  int _loadGeneration = 0;
  int _historyGeneration = 0;
  String _observedSupplier = '';
  DateTime? _observedDate;
  final Map<String, String?> _observedProducts = {};

  ReceiptFieldProvenance _owner(String field) => ReceiptFieldProvenance(
    origin: ReceiptFieldOrigin.ownerEdited,
    explanation: 'Owner entered or cleared $field.',
  );

  void _rememberValues() {
    _observedSupplier =
        '${draft.supplierId}|${draft.supplierName}|${draft.supplierBranch}';
    _observedDate = draft.purchasedAt;
    for (final line in draft.lines) {
      _observedProducts[line.id] = line.productId;
    }
  }

  /// Copy proposals back into existing editable objects so active editor rows
  /// retain their references. Raw evidence and owner values are never replaced.
  void _applySuggestions({bool matchProducts = true}) {
    final proposed = _suggestions.suggest(
      draft,
      products: matchProducts ? products : const [],
      confirmedHistory: _confirmedHistory,
      importedAt: _importedAt,
    );
    draft.purchasedAt = proposed.purchasedAt;
    draft.hasPurchaseTime = proposed.hasPurchaseTime;
    draft.dateConfirmed = proposed.dateConfirmed;
    draft.dateFromReceipt = proposed.dateFromReceipt;
    draft.detectedTotalCents = proposed.detectedTotalCents;
    draft.totalIsPartial = proposed.totalIsPartial;
    draft.provenance
      ..clear()
      ..addAll(proposed.provenance);
    for (var i = 0; i < draft.lines.length; i++) {
      final line = draft.lines[i];
      final value = proposed.lines[i];
      line.productId = value.productId;
      line.matchOrigin = value.matchOrigin;
      line.quantity = value.quantity;
      line.unit = value.unit;
      line.piecesPerPack = value.piecesPerPack;
      line.grossAmountCents = value.grossAmountCents;
      line.confirmed = value.confirmed;
      line.provenance
        ..clear()
        ..addAll(value.provenance);
    }
    _rememberValues();
  }

  /// History queries are confirmed-only. A superseded query cannot mutate a
  /// different supplier/product selection or a disposed review.
  Future<void> refreshSuggestions({bool apply = true}) async {
    final generation = ++_historyGeneration;
    final supplierId = draft.supplierId;
    if (apply) _applySuggestions();
    final ids = draft.lines
        .map((line) => line.productId)
        .whereType<String>()
        .where((id) => productFor(id) != null)
        .toSet();
    final history = <PurchaseRecord>[];
    for (final id in ids) {
      final comparison = await adapter.getProductComparison(id);
      if (_disposed ||
          generation != _historyGeneration ||
          draft.supplierId != supplierId ||
          !draft.lines.any((line) => line.productId == id)) {
        return;
      }
      history.addAll(
        comparison.history
            .map((row) => row.purchase)
            .where((purchase) => purchase.productId == id),
      );
    }
    if (_disposed ||
        generation != _historyGeneration ||
        draft.supplierId != supplierId) {
      return;
    }
    _confirmedHistory
      ..clear()
      ..addAll(history);
    if (apply) _applySuggestions();
    _changed();
  }

  void setProduct(ParsedLineItem line, Product? product) {
    if (saving) return;
    line.productId = product?.id;
    line.matchOrigin = null;
    line.provenance[ReceiptSuggestionField.product] = _owner('product');
    changed(line: line);
  }

  void setPurchaseDate(DateTime? date, {bool hasTime = false}) {
    if (saving) return;
    draft.purchasedAt = date;
    draft.hasPurchaseTime = hasTime;
    draft.dateManuallyEdited = true;
    draft.dateConfirmed = false;
    draft.dateFromReceipt = false;
    draft.provenance[ReceiptMetadataField.purchasedAt] = _owner(
      'purchase date',
    );
    changed();
  }

  List<ReceiptOcrPage> get pages => draft.ocrPages.isNotEmpty
      ? draft.ocrPages
      : draft.imagePaths.indexed
            .map(
              (entry) => ReceiptOcrPage(
                imagePath: entry.$2,
                recognitionImagePath: entry.$1 == 0
                    ? draft.recognitionImagePath
                    : null,
                textLines: draft.imagePaths.length == 1
                    ? draft.textLines
                    : const [],
              ),
            )
            .toList();

  void selectPage(int index) {
    if (saving || index < 0 || index >= pages.length) return;
    selectedPage = index;
    _changed();
  }

  void editText(ParsedLineItem line, ReceiptLineField field, String text) {
    if (saving) return;
    final previousProduct = line.productId;
    switch (field) {
      case ReceiptLineField.description:
        line.description = text;
        line.provenance[ReceiptSuggestionField.description] = _owner(
          'description',
        );
        line.provenance.remove(ReceiptSuggestionField.product);
        line.productId = null;
        line.matchOrigin = null;
        final product = receiptProductMatch(text, products);
        if (product != null) {
          line.productId = product.id;
          line.matchOrigin = 'Matched from receipt';
          line.provenance[ReceiptSuggestionField.product] =
              const ReceiptFieldProvenance(
                origin: ReceiptFieldOrigin.calculated,
                explanation:
                    'Unique exact catalog identity from owner description.',
              );
        }
        _observedProducts[line.id] = line.productId;
      case ReceiptLineField.quantity:
        line.quantity = parseQuantity(text);
        line.quantityEdited = true;
        line.provenance[ReceiptSuggestionField.quantity] = _owner('quantity');
      case ReceiptLineField.piecesPerPack:
        line.piecesPerPack = parseQuantity(text);
        line.provenance[ReceiptSuggestionField.piecesPerPack] = _owner(
          'pieces per pack',
        );
      case ReceiptLineField.amount:
        line.grossAmountCents = parsePesos(text);
        line.amountEdited = true;
        line.provenance[ReceiptSuggestionField.amount] = _owner('amount');
    }
    changed(line: line, affectsTotal: field == ReceiptLineField.amount);
    if (previousProduct != line.productId && !loading) {
      _refreshHistoryAfterEdit();
    }
  }

  void setUnit(ParsedLineItem line, PurchaseUnit unit) {
    if (saving) return;
    final previous = line.unit;
    line.unit = unit;
    line.provenance[ReceiptSuggestionField.unit] = _owner('purchase unit');
    line.provenance[ReceiptSuggestionField.piecesPerPack] = _owner(
      'pieces per pack',
    );
    if (unit == PurchaseUnit.piece) {
      line.piecesPerPack = 1;
    } else if (previous != PurchaseUnit.pack) {
      line.piecesPerPack = null;
    }
    changed(line: line);
  }

  bool _hasMatchedSupplier = false;
  bool _disposed = false;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final generation = ++_loadGeneration;
    loading = true;
    error = null;
    _changed();
    try {
      final catalog = await adapter.getProducts();
      if (_disposed || generation != _loadGeneration) return;
      products = catalog;
      final stores = await adapter.getSuppliers();
      if (_disposed || generation != _loadGeneration) return;
      suppliers = stores;
      if (_preserveOnNextLoad) {
        // Reopening loads choices/history for later owner edits, but never
        // regenerates persisted proposals or re-normalizes their raw evidence.
        await refreshSuggestions(apply: false);
        if (_disposed || generation != _loadGeneration) return;
        _preserveOnNextLoad = false;
        _hasMatchedSupplier = true;
        _rememberValues();
        return;
      }
      if (draft.supplierId == null) {
        final matches = suppliers
            .where(
              (supplier) =>
                  _key(supplier.name) == _key(draft.supplierName) &&
                  (draft.supplierBranch.isEmpty ||
                      _key(supplier.branch) == _key(draft.supplierBranch)),
            )
            .toList();
        if (matches.length == 1) draft.supplierId = matches.single.id;
      }
      for (final supplier in suppliers) {
        if (supplier.id == draft.supplierId) {
          draft.supplierName = supplier.name;
          draft.supplierBranch = supplier.branch;
          draft.supplierNotes = '';
          break;
        }
      }
      refreshDateSuggestion();
      _hasMatchedSupplier = true;
      // Unique confirmed aliases or complete exact catalog identities prefill
      // product identity. Similar catalog names still need an explicit choice.
      final aliases = <String, List<ProductMatchSuggestion>>{};
      for (final line in draft.lines) {
        if (line.productId != null ||
            line.description.trim().isEmpty ||
            line.provenance[ReceiptSuggestionField.product]?.origin ==
                ReceiptFieldOrigin.ownerEdited) {
          continue;
        }
        final description = line.description;
        final supplierId = draft.supplierId;
        final key = '${supplierId ?? ''}|${_key(description)}';
        final matches = aliases[key] ??= await adapter.matchAliases(
          description,
          supplierId: supplierId,
        );
        if (_disposed ||
            generation != _loadGeneration ||
            line.description != description ||
            draft.supplierId != supplierId ||
            line.productId != null ||
            line.provenance[ReceiptSuggestionField.product]?.origin ==
                ReceiptFieldOrigin.ownerEdited) {
          continue;
        }
        final exactIds = matches
            .where((match) => match.exactAlias)
            .map((match) => match.product.id)
            .where((id) => productFor(id) != null)
            .toSet();
        if (exactIds.length == 1) {
          line.productId = exactIds.single;
          line.matchOrigin = 'Previously matched';
          line.provenance[ReceiptSuggestionField.product] =
              const ReceiptFieldProvenance(
                origin: ReceiptFieldOrigin.history,
                explanation: 'Unique confirmed supplier alias.',
              );
          line.confirmed = false;
        } else if (exactIds.isEmpty) {
          final product = receiptProductMatch(line.description, products);
          if (product != null) {
            line.productId = product.id;
            line.matchOrigin = 'Matched from receipt';
            line.provenance[ReceiptSuggestionField.product] =
                const ReceiptFieldProvenance(
                  origin: ReceiptFieldOrigin.calculated,
                  explanation: 'Unique exact catalog brand, variant and size.',
                );
            line.confirmed = false;
          }
        }
      }
      if (_disposed || generation != _loadGeneration) return;
      await refreshSuggestions();
    } catch (failure) {
      if (!_disposed && generation == _loadGeneration) {
        error = userMessage(failure);
      }
    } finally {
      if (!_disposed && generation == _loadGeneration) {
        loading = false;
        _changed();
      }
    }
  }

  /// Re-evaluate only OCR-derived dates. An owner edit always wins over reload
  /// or a changed supplier preference; no saved purchase is modified here.
  void refreshDateSuggestion() {
    if (draft.dateManuallyEdited || draft.dateConfirmed) return;
    final source = pages
        .expand(
          (page) => [...recognizedReceiptText(page.textLines).split('\n'), ''],
        )
        .toList();
    if (source.every((row) => row.trim().isEmpty)) return;
    final supplier = suppliers
        .where((value) => value.id == draft.supplierId)
        .firstOrNull;
    final suggestion = ReceiptPurchaseDateTime().suggest(
      source,
      dateOrder: supplier?.dateOrder,
    );
    draft.provenance.remove(ReceiptMetadataField.purchasedAt);
    draft.purchasedAt = suggestion.purchasedAt;
    draft.hasPurchaseTime = suggestion.hasPurchaseTime;
    draft.dateFromReceipt = suggestion.purchasedAt != null;
    draft.dateCandidates = suggestion.candidates;
  }

  Future<void> chooseDateCandidate(
    PurchaseDateCandidate candidate, {
    bool remember = false,
  }) async {
    if (saving || loading || !draft.dateCandidates.contains(candidate)) return;
    final supplierId = draft.supplierId;
    if (remember) {
      final supplier = suppliers
          .where((value) => value.id == supplierId)
          .firstOrNull;
      if (supplier == null) {
        throw const ValidationException('Select a saved supplier first.');
      }
      await adapter.saveSupplier(
        Supplier(
          id: supplier.id,
          name: supplier.name,
          branch: supplier.branch,
          notes: supplier.notes,
          dateOrder: candidate.order,
        ),
      );
    }
    if (_disposed ||
        draft.supplierId != supplierId ||
        draft.dateManuallyEdited) {
      return;
    }
    draft.purchasedAt = candidate.date;
    draft.hasPurchaseTime = candidate.hasTime;
    draft.dateFromReceipt = true;
    draft.dateManuallyEdited = true;
    draft.provenance[ReceiptMetadataField.purchasedAt] = _owner(
      'purchase date',
    );
    draft.dateConfirmed = false;
    changed();
  }

  static String _key(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Product? productFor(String? id) {
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }

  void changed({ParsedLineItem? line, bool affectsTotal = false}) {
    if (_disposed) return;
    _resetPendingCommand();
    final supplierChanged =
        _observedSupplier !=
        '${draft.supplierId}|${draft.supplierName}|${draft.supplierBranch}';
    if (supplierChanged) {
      draft.provenance[ReceiptMetadataField.supplier] = _owner('supplier');
      _confirmedHistory.clear();
      ++_historyGeneration;
    }
    if (draft.dateManuallyEdited && draft.purchasedAt != _observedDate) {
      draft.provenance[ReceiptMetadataField.purchasedAt] = _owner(
        'purchase date',
      );
      draft.dateConfirmed = false;
    }
    final productChanged =
        line != null && _observedProducts[line.id] != line.productId;
    if (productChanged) {
      line.provenance[ReceiptSuggestionField.product] = _owner('product');
      ++_historyGeneration;
    }
    if (_hasMatchedSupplier && supplierChanged) {
      for (final item in draft.lines) {
        if (item.matchOrigin == 'Previously matched') {
          item.productId = null;
          item.matchOrigin = null;
          item.provenance.remove(ReceiptSuggestionField.product);
          item.confirmed = false;
        }
      }
      load();
    }
    if (line != null) line.confirmed = false;
    _applySuggestions(matchProducts: !supplierChanged);
    if (productChanged && !loading) {
      refreshSuggestions().catchError((Object failure) {
        if (!_disposed) {
          error = userMessage(failure);
          _changed();
        }
      });
    }
    if (affectsTotal) draft.totalDifferenceConfirmed = false;
    draft.allowDuplicate = false;
    _changed();
  }

  void _refreshHistoryAfterEdit() {
    refreshSuggestions().catchError((Object failure) {
      if (!_disposed) {
        error = userMessage(failure);
        _changed();
      }
    });
  }

  void addLine() {
    if (saving) return;
    _resetPendingCommand();
    final line = ParsedLineItem();
    _prepareLine(line);
    draft.lines.add(line);
    _applySuggestions();
    draft.totalDifferenceConfirmed = false;
    draft.allowDuplicate = false;
    _changed();
  }

  void removeLine(ParsedLineItem line) {
    if (saving) return;
    _resetPendingCommand();
    draft.lines.remove(line);
    _applySuggestions();
    draft.allowDuplicate = false;
    for (final remaining in draft.lines) {
      if (remaining.possibleDuplicateOf == line.id) {
        remaining.possibleDuplicateOf = null;
        remaining.confirmed = false;
      }
    }
    draft.totalDifferenceConfirmed = false;
    _changed();
  }

  void confirmLine(ParsedLineItem line) {
    if (saving || lineProblem(line, requireConfirmation: false) != null) return;
    _resetPendingCommand();
    line.confirmed = true;
    _changed();
  }

  String? lineProblem(ParsedLineItem line, {bool requireConfirmation = true}) {
    if (line.possibleDuplicateOf != null) {
      return 'Resolve the possible overlap with the previous photo.';
    }
    if (line.description.trim().isEmpty) {
      return 'Enter the product name.';
    }
    if (line.productId != null && productFor(line.productId) == null) {
      return 'This product is no longer available. Choose another product.';
    }
    if (line.quantity == null ||
        line.quantity! <= 0 ||
        line.quantity! > maxQuantity) {
      return 'Enter a valid whole purchase quantity.';
    }
    if (line.unit == null) return 'Choose pieces or packs.';
    if (line.unit == PurchaseUnit.piece &&
        line.piecesPerPack != null &&
        line.piecesPerPack != 1) {
      return 'Individual pieces must use one piece per unit. Choose pieces again.';
    }
    if (line.unit == PurchaseUnit.pack &&
        (line.piecesPerPack == null ||
            line.piecesPerPack! <= 0 ||
            line.piecesPerPack! > maxQuantity)) {
      return 'Enter the confirmed pieces per pack.';
    }
    if (line.grossAmountCents == null ||
        line.grossAmountCents! <= 0 ||
        line.grossAmountCents! > maxAmountCents) {
      return 'Enter the total amount paid for this item.';
    }
    if (line.discountCents < 0 ||
        line.discountCents >= line.grossAmountCents!) {
      return 'Check the amount paid for this item.';
    }
    if (requireConfirmation && !line.confirmed) {
      return 'Check and confirm this product, quantity, and amount.';
    }
    return null;
  }

  int get confirmedCount => draft.lines.where((line) => line.confirmed).length;

  int? get lineTotalCents {
    var sum = 0;
    for (final line in draft.lines) {
      final gross = line.grossAmountCents;
      if (gross == null ||
          gross <= 0 ||
          gross > maxAmountCents ||
          line.discountCents < 0 ||
          line.discountCents >= gross) {
        return null;
      }
      sum += line.netAmountCents!;
    }
    return sum;
  }

  bool get hasTotalDifference =>
      draft.detectedTotalCents != null &&
      lineTotalCents != null &&
      draft.detectedTotalCents != lineTotalCents;

  String? get problem {
    if (draft.supplierName.trim().isEmpty) {
      return 'Enter or choose the supplier.';
    }
    if (draft.purchasedAt == null || !draft.dateConfirmed) {
      return 'Choose and confirm the purchase date.';
    }
    if (draft.lines.isEmpty) return 'Add at least one purchase line.';
    if (draft.lines.length > 1000) {
      return 'Save no more than 1,000 items on one receipt.';
    }
    for (var index = 0; index < draft.lines.length; index++) {
      final issue = lineProblem(draft.lines[index]);
      if (issue != null) return 'Line ${index + 1}: $issue';
    }
    if ((lineTotalCents ?? 0) > maxAmountCents) {
      return 'This purchase total exceeds the supported amount.';
    }
    if (hasTotalDifference && !draft.totalDifferenceConfirmed) {
      return 'Review and acknowledge the difference from the detected receipt total.';
    }
    return null;
  }

  Future<SaveReceiptResult> save() async {
    if (saving) {
      throw const ValidationException('This receipt is already being saved.');
    }
    if (pendingId != null || correctionOfReceiptId != null) {
      throw const ValidationException(
        'Save Needs review, then confirm from the saved receipt.',
      );
    }
    final issue = problem;
    if (issue != null) throw ValidationException(issue);
    saving = true;
    error = null;
    _changed();
    try {
      return await adapter.saveConfirmedReceipt(draft);
    } finally {
      saving = false;
      _changed();
    }
  }

  void _resetPendingCommand() {
    _pendingCommand = null;
  }

  /// Resume the already prepared private snapshot returned from Review, without
  /// regenerating import dates, prices or aliases. An unchanged return preserves
  /// the exact pending command; an owner edit starts a new command on next save.
  ReceiptReviewState resumeSnapshot(ReceiptDraft returned) {
    if (loading || saving || _disposed) {
      throw StateError(
        'Wait for the prepared review before returning a snapshot.',
      );
    }
    final resumed = ReceiptReviewState(
      adapter: adapter,
      draft: returned,
      pendingId: pendingId,
      expectedRevision: expectedRevision,
      correctionOfReceiptId: correctionOfReceiptId,
      expectedConfirmedRevision: expectedConfirmedRevision,
      importedAt: _importedAt,
      preserveSuggestions: true,
    );
    resumed.products = List.of(products);
    resumed.suppliers = List.of(suppliers);
    resumed._confirmedHistory.addAll(_confirmedHistory);
    resumed._hasMatchedSupplier = _hasMatchedSupplier;
    resumed.loading = false;
    resumed._preserveOnNextLoad = false;
    if (ReceiptSnapshotCodec().encode(draft) ==
        ReceiptSnapshotCodec().encode(resumed.draft)) {
      resumed._pendingCommand = _pendingCommand;
    }
    return resumed;
  }

  /// A duplicate override changes the payload and therefore starts a new command.
  void allowPendingDuplicate() {
    if (saving) return;
    draft.allowDuplicate = true;
    _resetPendingCommand();
  }

  /// Pending receipts retain unresolved values. Confirmation validation belongs
  /// to save()/the storage boundary, never to this evidence-preserving action.
  /// A failed command retries its frozen private payload and UUID unchanged.
  Future<PendingSaveResult> savePending() async {
    if (saving || loading) {
      throw const ValidationException(
        'Wait for this receipt to finish preparing or saving.',
      );
    }
    _pendingCommand ??= PendingReceiptSaveCommand(
      draft: draft,
      pendingId: pendingId,
      expectedRevision: expectedRevision,
      correctionOfReceiptId: correctionOfReceiptId,
      expectedConfirmedRevision: expectedConfirmedRevision,
    );
    saving = true;
    error = null;
    _changed();
    try {
      final result = await _pendingCommand!.submit(adapter);
      pendingId = result.id;
      expectedRevision = result.revision;
      return result;
    } finally {
      saving = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
