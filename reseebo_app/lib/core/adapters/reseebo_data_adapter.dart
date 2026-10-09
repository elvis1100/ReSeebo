import '../models/store_profile.dart';
import '../models/product.dart';
import '../models/supplier.dart';
import '../models/receipt.dart';
import '../models/comparison.dart';
import '../models/restock_estimate.dart';

/// Abstract contract governing all data communication between
/// UI screens and the local storage/OCR engines.
abstract class IReseeboDataAdapter {
  // Store Profile
  Future<StoreProfile> getStoreProfile();
  Future<void> updateStoreProfile(StoreProfile profile);

  // Products & Aliases
  Future<List<Product>> getProducts({String? query});
  Future<Product?> getProductById(String id);
  Future<void> saveProduct(Product product);
  Future<List<ProductMatchSuggestion>> matchAliases(String rawOcrDescription);

  // Suppliers
  Future<List<Supplier>> getSuppliers();
  Future<Supplier?> getSupplierById(String id);
  Future<void> saveSupplier(Supplier supplier);

  // Receipts
  Future<List<Receipt>> getRecentReceipts({int limit = 20});
  Future<ReceiptDraft> processReceiptImage(String localImagePath);
  Future<SaveReceiptResult> saveConfirmedReceipt(ReceiptDraft confirmedDraft);

  // Comparisons & Calculations
  Future<ProductComparisonData> getProductComparison(String productId);
  Future<RestockEstimate> calculateRestock({
    required String productId,
    required int targetPieces,
    required double additionalCost,
  });
  Future<ProfitCalculation> calculateProfit({
    required String productId,
    required double costPerPiece,
    double? customMarkupPercentage,
    double? customSellingPrice,
  });
}
