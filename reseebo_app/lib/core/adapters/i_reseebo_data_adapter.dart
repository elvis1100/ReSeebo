import '../models/models.dart';
import '../errors/app_exception.dart';
import '../models/latest_product_cost.dart';
import '../services/latest_product_cost_service.dart';
import '../services/pricing_service.dart';

export '../models/models.dart';
export '../errors/app_exception.dart';
export '../models/latest_product_cost.dart';

/// Every operation is local. Save methods validate at the storage boundary.
/// Image paths may be picker cache paths on input and become persistent on save.
abstract class IReseeboDataAdapter {
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
  Future<List<ProductMatchSuggestion>> matchAliases(String rawOcrDescription);
  Future<List<ProductAlias>> getAliases(String productId);
  Future<void> deleteAlias(String aliasId);
  Future<List<Receipt>> getRecentReceipts({int limit = 200, String? query});
  Future<ReceiptDetail> getReceipt(String receiptId);
  Future<ReceiptDraft> processReceiptImage(
    String localImagePath, {
    String? recognitionImagePath,
  });

  /// Recognize ordered pages of one receipt, retaining every original. Adjusted
  /// paths, if supplied, align one-for-one with originals. Repeated image bytes
  /// are rejected; possible repeated item rows require review before saving.
  Future<ReceiptDraft> processReceiptImages(
    List<String> localImagePaths, {
    List<String>? recognitionImagePaths,
  }) {
    if (localImagePaths.length != 1) {
      throw const ValidationException(
        'This adapter does not support multiple receipt pages.',
      );
    }
    return processReceiptImage(
      localImagePaths.single,
      recognitionImagePath: recognitionImagePaths?.single,
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
