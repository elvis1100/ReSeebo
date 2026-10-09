import 'product.dart';

/// One row in the multi-supplier comparison table.
class SupplierPriceRow {
  final String supplierId;
  final String supplierName;
  final String? branchLocation;
  final DateTime latestPurchaseDate;
  final String packageDescription; // e.g. "2 packs × 10 sachets"
  final double netAmountPaid;
  final double costPerPiece;
  final double differenceVsBest; // In pesos (0.0 if best)
  final bool isLowestPrice;
  final String sourceReceiptId;

  const SupplierPriceRow({
    required this.supplierId,
    required this.supplierName,
    this.branchLocation,
    required this.latestPurchaseDate,
    required this.packageDescription,
    required this.netAmountPaid,
    required this.costPerPiece,
    required this.differenceVsBest,
    this.isLowestPrice = false,
    required this.sourceReceiptId,
  });
}

/// Chronological price record at a specific supplier over time.
class PriceHistoryRecord {
  final DateTime purchaseDate;
  final double costPerPiece;
  final double? changeFromPreviousPesos;
  final double? changeFromPreviousPercent;
  final String packageDetails;
  final String sourceReceiptId;

  const PriceHistoryRecord({
    required this.purchaseDate,
    required this.costPerPiece,
    this.changeFromPreviousPesos,
    this.changeFromPreviousPercent,
    required this.packageDetails,
    required this.sourceReceiptId,
  });
}

/// Aggregated comparison dataset for a product.
class ProductComparisonData {
  final Product product;
  final List<SupplierPriceRow> supplierRows;
  final List<PriceHistoryRecord> historyRows;
  final double? lowestHistoricalPrice;
  final DateTime? lowestHistoricalDate;
  final String? lowestHistoricalSupplierName;

  const ProductComparisonData({
    required this.product,
    required this.supplierRows,
    required this.historyRows,
    this.lowestHistoricalPrice,
    this.lowestHistoricalDate,
    this.lowestHistoricalSupplierName,
  });

  /// The most affordable supplier from recent purchases
  SupplierPriceRow? get bestRecentSupplier {
    if (supplierRows.isEmpty) return null;
    return supplierRows.firstWhere(
      (r) => r.isLowestPrice,
      orElse: () => supplierRows.first,
    );
  }
}
