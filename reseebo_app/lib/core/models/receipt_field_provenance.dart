/// A value's origin stays separate from owner confirmation and raw OCR evidence.
enum ReceiptFieldOrigin { extracted, calculated, history, assumed, ownerEdited }

enum ReceiptMetadataField { supplier, purchasedAt, total }

enum ReceiptSuggestionField {
  description,
  product,
  quantity,
  unit,
  piecesPerPack,
  amount,
}

class ReceiptFieldProvenance {
  const ReceiptFieldProvenance({
    required this.origin,
    required this.explanation,
    this.sourcePurchaseId,
    this.sourceReceiptId,
    this.sourceSupplierId,
    this.sourceSupplierName,
    this.sourcePurchasedAt,
  });
  final ReceiptFieldOrigin origin;
  final String explanation;
  final String? sourcePurchaseId;
  final String? sourceReceiptId;
  final String? sourceSupplierId;
  final String? sourceSupplierName;
  final DateTime? sourcePurchasedAt;
}
