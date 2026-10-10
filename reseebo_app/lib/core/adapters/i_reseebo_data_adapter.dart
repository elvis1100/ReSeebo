import '../models/models.dart';
import '../models/ocr_engine.dart';
import '../models/pending_receipt.dart';
import '../models/confirmed_receipt.dart';
import '../errors/app_exception.dart';
import '../models/latest_product_cost.dart';
import '../services/latest_product_cost_service.dart';
import '../services/pricing_service.dart';
import '../services/ocr_engine_registry.dart';

export '../models/models.dart';
export '../models/ocr_engine.dart';
export '../models/pending_receipt.dart';
export '../models/confirmed_receipt.dart';
export '../errors/app_exception.dart';
export '../models/latest_product_cost.dart';

/// Every operation is local. Save methods validate at the storage boundary.
/// Image paths may be picker cache paths on input and become persistent on save.
abstract class IReseeboDataAdapter {
  Future<List<OcrEngineDescriptor>> getOcrEngines() async => const [
    OcrEngineRegistry.mlKitDescriptor,
  ];

  /// Frees capture inference resources without closing the shared database.
  Future<void> releaseOcrSession() async {}

  Future<StoreProfile> getStoreProfile();
  Future<void> updateStoreProfile(StoreProfile profile);
  Future<List<Product>> getProducts({String? query});
  Future<Product?> getProductById(String id);
  Future<void> saveProduct(Product product);
  Future<List<String>> getProductCategories();
  Future<void> addProductCategory(String name);

  /// Removes the category and clears its product assignments atomically.
  /// Products and purchase history remain intact.
  Future<void> removeProductCategory(String name);
  Future<List<Supplier>> getSuppliers();
  Future<Supplier?> getSupplierById(String id) async {
    final list = await getSuppliers();
    return list.where((s) => s.id == id).firstOrNull;
  }

  Future<void> saveSupplier(Supplier supplier);
  Future<List<ProductMatchSuggestion>> matchAliases(
    String rawOcrDescription, {
    String? supplierId,
  });
  Future<List<ProductAlias>> getAliases(String productId);
  Future<void> deleteAlias(String aliasId);
  Future<List<Receipt>> getRecentReceipts({int limit = 200, String? query});
  Future<ReceiptDetail> getReceipt(String receiptId);

  /// Stores nullable evidence without creating confirmed catalog/history rows.
  /// Insert omits expectedRevision; edits require it. Freeze the payload and
  /// command operation ID across retries; changed details need a fresh ID.
  Future<PendingSaveResult> savePendingReceipt(
    ReceiptDraft draft, {
    required String operationId,
    String? pendingId,
    int? expectedRevision,
    String? correctionOfReceiptId,
    int? expectedConfirmedRevision,
  });
  Future<PendingReceipt> getPendingReceipt(String id);

  /// Confirms the exact pending revision. A frozen command ID returns its
  /// original result after retries, deletion or later corrections; changed
  /// commands and stale pending/confirmed revisions throw typed exceptions.
  Future<SaveReceiptResult> confirmPendingReceipt(
    String id, {
    required int expectedRevision,
    required String operationId,
  });
  Future<ConfirmedReceiptEdit> getConfirmedReceiptEdit(String receiptId);
  Future<List<ReceiptRevision>> getReceiptRevisions(String receiptId);

  /// Resolves a retained import route after confirmation removed its pending row.
  Future<String?> resolveConfirmedReceiptId(String pendingId);
  Future<List<LedgerEntry>> getLedgerEntries({int limit = 200, String? query});
  Future<ReceiptDraft> processReceiptImage(
    String localImagePath, {
    String? recognitionImagePath,
    String? comparisonImagePath,
    OcrEngineId engineId = OcrEngineId.mlKit,
  });

  /// Recognize ordered pages of one receipt, retaining every original. Adjusted
  /// paths, if supplied, align one-for-one with originals. Repeated image bytes
  /// are rejected; possible repeated item rows require review before saving.
  Future<ReceiptDraft> processReceiptImages(
    List<String> localImagePaths, {
    List<String>? recognitionImagePaths,
    List<String>? comparisonImagePaths,
    OcrEngineId engineId = OcrEngineId.mlKit,
    String preprocessingRevision = '1',
  }) {
    if (localImagePaths.length != 1) {
      throw const ValidationException(
        'This adapter does not support multiple receipt pages.',
      );
    }
    return processReceiptImage(
      localImagePaths.single,
      recognitionImagePath: recognitionImagePaths?.single,
      comparisonImagePath: comparisonImagePaths?.single,
      engineId: engineId,
    );
  }

  /// Reusing an operation ID with the same content returns the existing receipt.
  /// Edited content needs a fresh operation ID. Possible imports throw
  /// DuplicateReceiptException unless the owner explicitly confirms them.
  /// A selected supplier ID must match the confirmed name/branch. Draft supplier
  /// notes initialize new suppliers only; existing notes use saveSupplier.
  /// Confirmed lines without a product ID create name-only catalog products
  /// without photos, atomically with receipt lines. Matching remains optional.
  Future<SaveReceiptResult> saveConfirmedReceipt(ReceiptDraft confirmedDraft);
  Future<ProductComparisonData> getProductComparison(String productId);

  /// Returns dashboard cost/date summaries for requested products with history;
  /// empty IDs return an empty map. First select each supplier's latest purchase
  /// by date, then time when every purchase on that supplier/date has a time,
  /// then saved sequence. Rank those supplier candidates by date, then time
  /// when every candidate on that product/date has a time, then recorded-at and
  /// saved sequence. Missing times therefore never imply midnight ordering.
  /// The default supports adapters using comparisons; SQLite returns only the
  /// final summaries without hydrating purchase history or receipt images.
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

  /// Estimate whole recorded packs using historical prices. [additionalCost]
  /// is a peso fallback for each supplier; [additionalCostsCents] overrides it
  /// per supplier in centavos. Invalid quantities/amounts throw AppException.
  Future<RestockEstimate> calculateRestock({
    required String productId,
    required int targetPieces,
    required double additionalCost,
    Map<String, int> additionalCostsCents = const {},
  });

  /// Group the lowest known product subtotals, add extras once per supplier,
  /// and retain alternatives with explicitly missing price records. Grouped
  /// product minima do not necessarily minimize a trip's total including extras.
  Future<BasketEstimate> calculateBasket(
    Map<String, int> targetPieces, {
    Map<String, int> additionalCostsCents = const {},
  });
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

  Future<void> close();
}
