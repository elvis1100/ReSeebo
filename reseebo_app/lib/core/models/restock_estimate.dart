/// Breakdown of restock calculation for a supplier option.
class RestockSupplierOption {
  final String supplierId;
  final String supplierName;
  final DateTime priceDate;
  final int piecesPerPack;
  final double packCost;
  final int packsNeeded; // Rounded UP (ceil) to never short-change the store
  final int totalPiecesPurchased;
  final double totalPurchaseCost;
  final double travelCost;
  final double totalCostWithTravel;
  final double grossSavingsVsAlternate;
  final double netSavingsAfterTravel;

  const RestockSupplierOption({
    required this.supplierId,
    required this.supplierName,
    required this.priceDate,
    required this.piecesPerPack,
    required this.packCost,
    required this.packsNeeded,
    required this.totalPiecesPurchased,
    required this.totalPurchaseCost,
    this.travelCost = 0.0,
    required this.totalCostWithTravel,
    this.grossSavingsVsAlternate = 0.0,
    this.netSavingsAfterTravel = 0.0,
  });
}

/// Overall restock planning calculation across suppliers.
class RestockEstimate {
  final String productId;
  final int targetPieces;
  final List<RestockSupplierOption> supplierOptions;

  const RestockEstimate({
    required this.productId,
    required this.targetPieces,
    required this.supplierOptions,
  });

  RestockSupplierOption? get recommendedSupplier {
    if (supplierOptions.isEmpty) return null;
    final sorted = List<RestockSupplierOption>.from(supplierOptions)
      ..sort((a, b) => a.totalCostWithTravel.compareTo(b.totalCostWithTravel));
    return sorted.first;
  }
}

/// Selling price and estimated gross profit (Tubo) per piece.
class ProfitCalculation {
  final double costPerPiece;
  final double markupPercentageUsed;
  final bool isProductOverride;
  final double suggestedSellingPrice;
  final double? ownerSetSellingPrice;
  final double estimatedGrossProfit;
  final double grossMarginPercentage;

  const ProfitCalculation({
    required this.costPerPiece,
    required this.markupPercentageUsed,
    required this.isProductOverride,
    required this.suggestedSellingPrice,
    this.ownerSetSellingPrice,
    required this.estimatedGrossProfit,
    required this.grossMarginPercentage,
  });

  /// Factory that calculates suggested price and gross profit accurately
  factory ProfitCalculation.compute({
    required double costPerPiece,
    required double markupPercentage,
    bool isProductOverride = false,
    double? ownerSetSellingPrice,
  }) {
    final suggested = costPerPiece * (1.0 + (markupPercentage / 100.0));
    final effectiveSellingPrice = ownerSetSellingPrice ?? suggested;
    final profit = effectiveSellingPrice - costPerPiece;
    final margin = effectiveSellingPrice > 0
        ? (profit / effectiveSellingPrice) * 100.0
        : 0.0;

    return ProfitCalculation(
      costPerPiece: costPerPiece,
      markupPercentageUsed: markupPercentage,
      isProductOverride: isProductOverride,
      suggestedSellingPrice: suggested,
      ownerSetSellingPrice: ownerSetSellingPrice,
      estimatedGrossProfit: profit,
      grossMarginPercentage: margin,
    );
  }
}
