/// Represents an individual purchased line item on a receipt.
class PurchaseLine {
  final String id;
  final String receiptId;
  final String productId;
  final String originalOcrDescription;
  final double quantityPurchased;
  final String unitType; // 'pack', 'pcs', 'box', 'sachet'
  final int piecesPerPack;
  final double netLineAmount;
  final double calculatedCostPerPiece;

  const PurchaseLine({
    required this.id,
    required this.receiptId,
    required this.productId,
    required this.originalOcrDescription,
    required this.quantityPurchased,
    this.unitType = 'pack',
    this.piecesPerPack = 1,
    required this.netLineAmount,
    required this.calculatedCostPerPiece,
  });

  /// Total number of individual sellable pieces in this purchase line
  int get totalPieces => (quantityPurchased * piecesPerPack).round();
}

/// Editable draft line item during receipt review before final confirmation.
class ParsedLineItem {
  String tempId;
  String rawDescription;
  String? matchedProductId;
  double quantity;
  String unitType;
  int piecesPerPack;
  double netAmount;
  double discount;
  bool isAmbiguous;

  ParsedLineItem({
    required this.tempId,
    required this.rawDescription,
    this.matchedProductId,
    this.quantity = 1.0,
    this.unitType = 'pack',
    this.piecesPerPack = 10,
    this.netAmount = 0.0,
    this.discount = 0.0,
    this.isAmbiguous = false,
  });

  /// Cost per individual piece calculated dynamically from draft inputs
  double get estimatedCostPerPiece {
    final totalUnits = quantity * (piecesPerPack <= 0 ? 1 : piecesPerPack);
    if (totalUnits <= 0) return 0.0;
    final effectiveAmount = (netAmount - discount) > 0 ? (netAmount - discount) : netAmount;
    return effectiveAmount / totalUnits;
  }
}
