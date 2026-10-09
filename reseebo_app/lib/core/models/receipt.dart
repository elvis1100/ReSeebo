import 'purchase_line.dart';

/// Persisted receipt record in SQLite.
class Receipt {
  final String id;
  final String supplierId;
  final DateTime purchaseDate;
  final String localImagePath;
  final DateTime recordedTimestamp;
  final String? receiptNumber;
  final String? notes;
  final double totalAmount;
  final int itemCount;

  const Receipt({
    required this.id,
    required this.supplierId,
    required this.purchaseDate,
    required this.localImagePath,
    required this.recordedTimestamp,
    this.receiptNumber,
    this.notes,
    required this.totalAmount,
    required this.itemCount,
  });
}

/// Editable draft state when scanning or reviewing a receipt.
class ReceiptDraft {
  String localImagePath;
  String? supplierId;
  String? supplierName;
  String? branchLocation;
  DateTime purchaseDate;
  String? receiptNumber;
  String? notes;
  List<ParsedLineItem> lines;
  bool isDuplicateSuspect;

  ReceiptDraft({
    required this.localImagePath,
    this.supplierId,
    this.supplierName,
    this.branchLocation,
    required this.purchaseDate,
    this.receiptNumber,
    this.notes,
    required this.lines,
    this.isDuplicateSuspect = false,
  });

  double get totalAmount =>
      lines.fold(0.0, (sum, line) => sum + (line.netAmount - line.discount));
}

/// Result returned after saving a receipt atomically.
class SaveReceiptResult {
  final String receiptId;
  final List<String> lineIds;
  final bool success;
  final String? errorMessage;

  const SaveReceiptResult({
    required this.receiptId,
    required this.lineIds,
    this.success = true,
    this.errorMessage,
  });
}
