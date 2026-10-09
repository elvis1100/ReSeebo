import 'package:uuid/uuid.dart';

const maxAmountCents = 100000000000;
const maxQuantity = 1000000;

class StoreProfile {
  const StoreProfile({
    this.name = '',
    this.ownerName = '',
    this.photoPath,
    this.defaultMarkupPercent,
  });
  final String name;
  final String ownerName;
  final String? photoPath;
  final double? defaultMarkupPercent;
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.brand,
    required this.variant,
    required this.size,
    this.category = '',
    this.barcode = '',
    this.photoPath,
    this.markupPercent,
    this.sellingPriceCents,
  });
  final String id;
  final String name;
  final String brand;
  final String variant;
  final String size;
  final String category;
  final String barcode;
  final String? photoPath;
  final double? markupPercent;
  final int? sellingPriceCents;
  String get identity => '$brand · $variant · $size';
}

class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.branch = '',
    this.notes = '',
  });
  final String id;
  final String name;
  final String branch;
  final String notes;
  String get label => branch.isEmpty ? name : '$name · $branch';
}

class ProductAlias {
  const ProductAlias({
    required this.id,
    required this.productId,
    required this.description,
  });
  final String id;
  final String productId;
  final String description;
}

class ProductMatchSuggestion {
  const ProductMatchSuggestion({
    required this.product,
    required this.reason,
    this.exactAlias = false,
  });
  final Product product;
  final String reason;
  final bool exactAlias;
}

enum PurchaseUnit { piece, pack }

class OcrTextLine {
  const OcrTextLine({
    required this.text,
    this.left = 0,
    this.top = 0,
    this.width = 0,
    this.height = 0,
  });
  final String text;
  final double left;
  final double top;
  final double width;
  final double height;
}

const maxReceiptPages = 20;

class ReceiptOcrPage {
  const ReceiptOcrPage({
    required this.imagePath,
    required this.textLines,
    this.recognitionImagePath,
  });
  final String imagePath;
  final String? recognitionImagePath;
  final List<OcrTextLine> textLines;
}

/// A draft is intentionally editable. Services snapshot it before any awaited
/// work; draft values are never treated as confirmed purchase history.
class ParsedLineItem {
  ParsedLineItem({
    String? id,
    this.description = '',
    this.productId,
    this.quantity,
    this.unit,
    this.piecesPerPack,
    this.grossAmountCents,
    this.discountCents = 0,
    this.confirmed = false,
    this.sourcePage = 0,
    this.possibleDuplicateOf,
    List<String>? warnings,
  }) : id = id ?? const Uuid().v4(),
       warnings = warnings ?? [];
  final String id;
  String description;
  String? productId;
  int? quantity;
  PurchaseUnit? unit;
  int? piecesPerPack;
  int? grossAmountCents;
  int discountCents;
  bool confirmed;
  int sourcePage;
  String? possibleDuplicateOf;
  final List<String> warnings;
  int? get netAmountCents =>
      grossAmountCents == null ? null : grossAmountCents! - discountCents;
  int? get totalPieces =>
      quantity == null ||
          unit == null ||
          (unit == PurchaseUnit.pack && piecesPerPack == null)
      ? null
      : quantity! * (unit == PurchaseUnit.piece ? 1 : piecesPerPack!);
  double? get costPerPieceCents =>
      (totalPieces ?? 0) <= 0 || (netAmountCents ?? 0) <= 0
      ? null
      : netAmountCents! / totalPieces!;
  ParsedLineItem snapshot() => ParsedLineItem(
    id: id,
    description: description,
    productId: productId,
    quantity: quantity,
    unit: unit,
    piecesPerPack: piecesPerPack,
    grossAmountCents: grossAmountCents,
    discountCents: discountCents,
    confirmed: confirmed,
    sourcePage: sourcePage,
    possibleDuplicateOf: possibleDuplicateOf,
    warnings: List.of(warnings),
  );
}

class ReceiptDraft {
  ReceiptDraft({
    String? operationId,
    required this.imagePath,
    List<String>? imagePaths,
    this.recognitionImagePath,
    this.supplierId,
    this.supplierName = '',
    this.supplierBranch = '',
    this.supplierNotes = '',
    this.purchasedAt,
    this.hasPurchaseTime = false,
    this.dateConfirmed = false,
    this.receiptNumber = '',
    this.notes = '',
    this.rawText = '',
    this.detectedTotalCents,
    this.totalDifferenceConfirmed = false,
    this.allowDuplicate = false,
    List<OcrTextLine>? textLines,
    List<ParsedLineItem>? lines,
    List<String>? warnings,
  }) : imagePaths = List.unmodifiable(imagePaths ?? [imagePath]),
       operationId = operationId ?? const Uuid().v4(),
       lines = lines ?? [],
       textLines = textLines ?? [],
       warnings = warnings ?? [];
  final String operationId;
  final String imagePath;
  final List<String> imagePaths;
  final String? recognitionImagePath;
  String? supplierId;
  String supplierName;
  String supplierBranch;
  String supplierNotes;
  DateTime? purchasedAt;
  bool hasPurchaseTime;
  bool dateConfirmed;
  String receiptNumber;
  String notes;
  String rawText;
  int? detectedTotalCents;
  bool totalDifferenceConfirmed;
  bool allowDuplicate;
  final List<OcrTextLine> textLines;
  final List<ParsedLineItem> lines;
  final List<String> warnings;
  ReceiptDraft snapshot() => ReceiptDraft(
    operationId: operationId,
    imagePath: imagePath,
    imagePaths: imagePaths,
    recognitionImagePath: recognitionImagePath,
    supplierId: supplierId,
    supplierName: supplierName,
    supplierBranch: supplierBranch,
    supplierNotes: supplierNotes,
    purchasedAt: purchasedAt,
    hasPurchaseTime: hasPurchaseTime,
    dateConfirmed: dateConfirmed,
    receiptNumber: receiptNumber,
    notes: notes,
    rawText: rawText,
    detectedTotalCents: detectedTotalCents,
    totalDifferenceConfirmed: totalDifferenceConfirmed,
    allowDuplicate: allowDuplicate,
    textLines: List.of(textLines),
    lines: lines.map((line) => line.snapshot()).toList(),
    warnings: List.of(warnings),
  );
}

class Receipt {
  const Receipt({
    required this.id,
    required this.supplier,
    required this.purchasedAt,
    required this.hasPurchaseTime,
    required this.createdAt,
    required this.imagePath,
    List<String> imagePaths = const [],
    required this.lineCount,
    required this.totalCents,
    this.receiptNumber = '',
    this.notes = '',
    // Keep the public parameter while deriving a fallback for legacy receipts.
    // ignore: prefer_initializing_formals
  }) : _imagePaths = imagePaths;
  final String id;
  final Supplier supplier;
  final DateTime purchasedAt;
  final bool hasPurchaseTime;
  final DateTime createdAt;
  final String imagePath;
  final List<String> _imagePaths;
  List<String> get imagePaths =>
      _imagePaths.isEmpty ? [imagePath] : List.unmodifiable(_imagePaths);
  final int lineCount;
  final int totalCents;
  final String receiptNumber;
  final String notes;
}

/// Costs use integer centavos and an integer piece denominator. A fractional
/// centavo cost is retained until a final payable/selling amount is rounded.
class PurchaseRecord {
  const PurchaseRecord({
    required this.id,
    required this.receiptId,
    required this.productId,
    required this.supplier,
    required this.purchasedAt,
    required this.hasPurchaseTime,
    required this.recordedAt,
    required this.originalDescription,
    required this.quantity,
    required this.unit,
    required this.piecesPerPack,
    required this.netAmountCents,
    required this.imagePath,
    this.discountCents = 0,
    this.receiptNumber = '',
    this.sequence = 0,
    this.sourcePage = 0,
  });
  final String id;
  final String receiptId;
  final String productId;
  final Supplier supplier;
  final DateTime purchasedAt;
  final bool hasPurchaseTime;
  final DateTime recordedAt;
  final String originalDescription;
  final int quantity;
  final PurchaseUnit unit;
  final int piecesPerPack;
  final int netAmountCents;
  final int discountCents;
  final String imagePath;
  final String receiptNumber;
  final int sequence;
  final int sourcePage;
  int get totalPieces => quantity * piecesPerPack;
  double get costPerPieceCents => netAmountCents / totalPieces;
  String get purchaseLabel => unit == PurchaseUnit.pack
      ? '$quantity packs × $piecesPerPack pcs'
      : '$quantity pcs';
}

class ReceiptDetail {
  const ReceiptDetail({required this.receipt, required this.lines});
  final Receipt receipt;
  final List<PurchaseRecord> lines;
}

class SaveReceiptResult {
  const SaveReceiptResult({
    required this.receiptId,
    required this.lineIds,
    required this.unitCostsCents,
    this.alreadySaved = false,
  });
  final String receiptId;
  final List<String> lineIds;
  final List<double> unitCostsCents;
  final bool alreadySaved;
}

class SupplierPriceRow {
  const SupplierPriceRow({
    required this.purchase,
    required this.bestCostPerPieceCents,
  });
  final PurchaseRecord purchase;
  final double bestCostPerPieceCents;
  double get differenceCents =>
      purchase.costPerPieceCents - bestCostPerPieceCents;
}

class PriceHistoryRecord {
  const PriceHistoryRecord({
    required this.purchase,
    this.previousCostPerPieceCents,
    this.orderingNote,
  });
  final PurchaseRecord purchase;
  final double? previousCostPerPieceCents;
  final String? orderingNote;
  double? get changeCents => previousCostPerPieceCents == null
      ? null
      : purchase.costPerPieceCents - previousCostPerPieceCents!;
  double? get changePercent => previousCostPerPieceCents == null
      ? null
      : changeCents! / previousCostPerPieceCents! * 100;
}

class ProductComparisonData {
  const ProductComparisonData({
    required this.product,
    required this.profile,
    required this.latestPrices,
    required this.history,
    this.lowestHistorical,
  });
  final Product product;
  final StoreProfile profile;
  final List<SupplierPriceRow> latestPrices;
  final List<PriceHistoryRecord> history;
  final PurchaseRecord? lowestHistorical;
  double? get effectiveMarkupPercent =>
      product.markupPercent ?? profile.defaultMarkupPercent;
}

class ProfitCalculation {
  const ProfitCalculation({
    required this.costPerPieceCents,
    required this.sellingPriceCents,
    required this.grossProfitCents,
    required this.markupPercent,
    required this.marginPercent,
  });
  final double costPerPieceCents;
  final int sellingPriceCents;
  final double grossProfitCents;
  final double markupPercent;
  final double? marginPercent;
}

class RestockSupplierEstimate {
  const RestockSupplierEstimate({
    required this.purchase,
    required this.targetPieces,
    required this.packsToBuy,
    required this.purchasedPieces,
    required this.subtotalCents,
    required this.additionalCostCents,
  });
  final PurchaseRecord purchase;
  final int targetPieces;
  final int packsToBuy;
  final int purchasedPieces;
  final int subtotalCents;
  final int additionalCostCents;
  int get totalCents => subtotalCents + additionalCostCents;
}

class RestockEstimate {
  const RestockEstimate({
    required this.product,
    required this.targetPieces,
    required this.suppliers,
  });
  final Product product;
  final int targetPieces;
  final List<RestockSupplierEstimate> suppliers;
}

class BasketItem {
  const BasketItem({required this.product, required this.estimate});
  final Product product;
  final RestockSupplierEstimate estimate;
}

class BasketSupplierGroup {
  const BasketSupplierGroup({
    required this.supplier,
    required this.items,
    required this.additionalCostCents,
  });
  final Supplier supplier;
  final List<BasketItem> items;
  final int additionalCostCents;
  int get subtotalCents =>
      items.fold(0, (sum, item) => sum + item.estimate.subtotalCents);
  int get totalCents => subtotalCents + additionalCostCents;
}

class BasketSupplierAlternative {
  const BasketSupplierAlternative({
    required this.supplier,
    required this.items,
    required this.missingProducts,
    required this.additionalCostCents,
  });
  final Supplier supplier;
  final List<BasketItem> items;
  final List<Product> missingProducts;
  final int additionalCostCents;
  int get knownSubtotalCents =>
      items.fold(0, (sum, item) => sum + item.estimate.subtotalCents);
  int get knownTotalCents => knownSubtotalCents + additionalCostCents;
}

class BasketEstimate {
  const BasketEstimate({
    required this.groups,
    required this.missingProducts,
    required this.alternatives,
  });
  final List<BasketSupplierGroup> groups;
  final List<Product> missingProducts;
  final List<BasketSupplierAlternative> alternatives;
  int get subtotalCents =>
      groups.fold(0, (sum, group) => sum + group.subtotalCents);
  int get totalCents => groups.fold(0, (sum, group) => sum + group.totalCents);
}
