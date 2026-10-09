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

  String get storeName => name;
  double get defaultMarkupPercentage => defaultMarkupPercent ?? 15.0;

  StoreProfile copyWith({
    String? name,
    String? storeName,
    String? ownerName,
    String? photoPath,
    double? defaultMarkupPercent,
    double? defaultMarkupPercentage,
  }) => StoreProfile(
    name: storeName ?? name ?? this.name,
    ownerName: ownerName ?? this.ownerName,
    photoPath: photoPath ?? this.photoPath,
    defaultMarkupPercent:
        defaultMarkupPercentage ??
        defaultMarkupPercent ??
        this.defaultMarkupPercent,
  );
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

  String get displayTitle => '$brand $variant $size'.trim();
  String get displayName => name.isNotEmpty ? name : displayTitle;
  String get sizeUnit => size;
  double? get markupPercentageOverride => markupPercent;
  double? get ownerSetSellingPrice =>
      sellingPriceCents != null ? sellingPriceCents! / 100.0 : null;

  Product copyWith({
    String? id,
    String? name,
    String? brand,
    String? variant,
    String? size,
    String? category,
    String? barcode,
    String? photoPath,
    double? markupPercent,
    int? sellingPriceCents,
  }) => Product(
    id: id ?? this.id,
    name: name ?? this.name,
    brand: brand ?? this.brand,
    variant: variant ?? this.variant,
    size: size ?? this.size,
    category: category ?? this.category,
    barcode: barcode ?? this.barcode,
    photoPath: photoPath ?? this.photoPath,
    markupPercent: markupPercent ?? this.markupPercent,
    sellingPriceCents: sellingPriceCents ?? this.sellingPriceCents,
  );
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
  String get displayName => label;
  String get branchLocation => branch;
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
  double get confidence => exactAlias ? 1.0 : 0.85;
}

enum PurchaseUnit { piece, pack }

/// A recognized word in pixel coordinates of its page's recognition image.
/// These bounds must never be overlaid on a differently cropped original.
class OcrTextToken {
  const OcrTextToken({
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

class OcrTextLine {
  const OcrTextLine({
    required this.text,
    this.left = 0,
    this.top = 0,
    this.width = 0,
    this.height = 0,
    this.tokens = const [],
  });
  final String text;
  final double left;
  final double top;
  final double width;
  final double height;
  final List<OcrTextToken> tokens;

  OcrTextLine snapshot() => OcrTextLine(
    text: text,
    left: left,
    top: top,
    width: width,
    height: height,
    tokens: List.unmodifiable(tokens),
  );
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

  ReceiptOcrPage snapshot() => ReceiptOcrPage(
    imagePath: imagePath,
    recognitionImagePath: recognitionImagePath,
    textLines: List.unmodifiable(textLines.map((line) => line.snapshot())),
  );
}

/// A draft is intentionally editable. Services snapshot it before any awaited
/// work; draft values are never treated as confirmed purchase history.
class ParsedLineItem {
  ParsedLineItem({
    String? id,
    String? tempId,
    String description = '',
    String? rawDescription,
    this.productId,
    this.quantity,
    this.unit,
    this.piecesPerPack,
    int? grossAmountCents,
    double? netAmount,
    this.discountCents = 0,
    this.confirmed = false,
    this.sourcePage = 0,
    this.possibleDuplicateOf,
    List<String>? warnings,
  }) : id = tempId ?? id ?? const Uuid().v4(),
       description = rawDescription ?? description,
       grossAmountCents = netAmount != null
           ? (netAmount * 100).round()
           : grossAmountCents,
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
  double? get unitCost =>
      costPerPieceCents != null ? costPerPieceCents! / 100.0 : null;
  double? get totalAmount =>
      netAmountCents != null ? netAmountCents! / 100.0 : null;
  double? get packPrice =>
      grossAmountCents != null ? grossAmountCents! / 100.0 : null;
  int get piecesPerPackValue => piecesPerPack ?? 1;
  int get packsCount => quantity ?? 1;

  String get rawDescription => description;
  set rawDescription(String v) => description = v;

  String? get matchedProductId => productId;
  set matchedProductId(String? v) => productId = v;

  bool get isAmbiguous => !confirmed;
  set isAmbiguous(bool v) => confirmed = !v;

  double get netAmount => (netAmountCents ?? 0) / 100.0;
  set netAmount(double v) => grossAmountCents = (v * 100).round();

  double? get estimatedCostPerPiece =>
      costPerPieceCents != null ? costPerPieceCents! / 100.0 : null;

  String get unitType => unit == PurchaseUnit.pack ? 'pack' : 'piece';
  set unitType(String v) =>
      unit = v == 'pack' ? PurchaseUnit.pack : PurchaseUnit.piece;

  double get discount => discountCents / 100.0;
  set discount(double v) => discountCents = (v * 100).round();
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
    String? imagePath,
    String? localImagePath,
    List<String>? imagePaths,
    this.recognitionImagePath,
    this.supplierId,
    this.supplierName = '',
    String? supplierBranch,
    String? branchLocation,
    this.supplierNotes = '',
    DateTime? purchasedAt,
    DateTime? purchaseDate,
    this.hasPurchaseTime = false,
    this.dateConfirmed = false,
    this.receiptNumber = '',
    this.notes = '',
    this.rawText = '',
    this.detectedTotalCents,
    this.totalDifferenceConfirmed = false,
    this.allowDuplicate = false,
    List<OcrTextLine>? textLines,
    List<ReceiptOcrPage>? ocrPages,
    List<ParsedLineItem>? lines,
    List<String>? warnings,
  }) : imagePath = localImagePath ?? imagePath ?? '',
       supplierBranch = branchLocation ?? supplierBranch ?? '',
       purchasedAt = purchaseDate ?? purchasedAt,
       imagePaths = List.unmodifiable(
         imagePaths ?? [localImagePath ?? imagePath ?? ''],
       ),
       operationId = operationId ?? const Uuid().v4(),
       lines = lines ?? [],
       textLines = textLines ?? [],
       ocrPages = ocrPages ?? [],
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
  final List<ReceiptOcrPage> ocrPages;
  final List<ParsedLineItem> lines;
  final List<String> warnings;

  String get localImagePath => imagePath;
  double get totalAmount => (detectedTotalCents ?? 0) / 100.0;
  int get lineItemCount => lines.length;
  DateTime get purchaseDate => purchasedAt ?? DateTime.now();
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
    textLines: textLines.map((line) => line.snapshot()).toList(),
    ocrPages: ocrPages.map((page) => page.snapshot()).toList(),
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

  String get supplierName => supplier.name;
  String get supplierId => supplier.id;
  DateTime get purchaseDate => purchasedAt;
  double get totalAmount => totalCents / 100.0;
  String get localImagePath => imagePath;
  int get lineItemCount => lineCount;
  int get itemCount => lineCount;
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

  double get unitCost => costPerPieceCents / 100.0;
  double get totalAmount => netAmountCents / 100.0;
  int get totalPiecesCount => totalPieces;
  String get supplierName => supplier.name;
}

typedef PurchaseLine = PurchaseRecord;

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

  double get difference => differenceCents / 100.0;
  double get differenceVsBest => difference;
  double get unitCost => purchase.costPerPieceCents / 100.0;
  double get costPerPiece => unitCost;
  String get supplierName => purchase.supplier.name;
  bool get isLowest => differenceCents == 0.0;
  bool get isLowestPrice => isLowest;
  String get sourceReceiptId => purchase.receiptId;
  String get packageDescription => purchase.purchaseLabel;
  DateTime get latestPurchaseDate => purchase.purchasedAt;
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

  double? get changeAmount => changeCents != null ? changeCents! / 100.0 : null;
  double? get changeFromPreviousPesos => changeAmount;
  double? get changeFromPreviousPercent => changePercent;
  double get unitCost => purchase.costPerPieceCents / 100.0;
  double get costPerPiece => unitCost;
  DateTime get date => purchase.purchasedAt;
  DateTime get purchaseDate => date;
  String get supplierName => purchase.supplier.name;
  String get sourceReceiptId => purchase.receiptId;
  String get packageDetails => purchase.purchaseLabel;
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

  double? get lowestHistoricalPrice => lowestHistorical?.unitCost;
  String? get lowestHistoricalSupplierName => lowestHistorical?.supplier.name;
  DateTime? get lowestHistoricalDate => lowestHistorical?.purchasedAt;
  List<SupplierPriceRow> get supplierRows => latestPrices;
  List<PriceHistoryRecord> get historyRows => history;
}

class ProfitCalculation {
  const ProfitCalculation({
    required this.costPerPieceCents,
    required this.sellingPriceCents,
    required this.grossProfitCents,
    required this.markupPercent,
    required this.marginPercent,
    this.ownerSetSellingPrice,
  });
  final double costPerPieceCents;
  final int sellingPriceCents;
  final double grossProfitCents;
  final double markupPercent;
  final double? marginPercent;
  final double? ownerSetSellingPrice;

  double get costPerPiece => costPerPieceCents / 100.0;
  double get suggestedSellingPrice => sellingPriceCents / 100.0;
  double get estimatedGrossProfit => grossProfitCents / 100.0;
  double get markupPercentageUsed => markupPercent;
  double? get grossMarginPercentage => marginPercent;

  static ProfitCalculation compute({
    required double costPerPiece,
    double? defaultMarkupPercentage,
    double? markupPercentage,
    double? customSellingPrice,
    double? ownerSetSellingPrice,
  }) {
    final effectiveMarkup = markupPercentage ?? defaultMarkupPercentage ?? 15.0;
    final effectiveSelling = ownerSetSellingPrice ?? customSellingPrice;
    final costCents = costPerPiece * 100.0;
    final sellingCents = effectiveSelling != null
        ? (effectiveSelling * 100.0).round()
        : (costCents * (1 + effectiveMarkup / 100)).round();
    final gross = sellingCents - costCents;
    return ProfitCalculation(
      costPerPieceCents: costCents,
      sellingPriceCents: sellingCents,
      grossProfitCents: gross,
      markupPercent: effectiveMarkup,
      marginPercent: sellingCents == 0 ? null : (gross / sellingCents * 100),
      ownerSetSellingPrice: effectiveSelling,
    );
  }
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

  int get packsNeeded => packsToBuy;
  int get totalPurchasedPieces => purchasedPieces;
  int get totalPiecesPurchased => purchasedPieces;
  double get calculatedSubtotal => subtotalCents / 100.0;
  double get totalEstimatedCost =>
      (subtotalCents + additionalCostCents) / 100.0;
  double get totalPurchaseCost => subtotalCents / 100.0;
  double get travelCost => additionalCostCents / 100.0;
  double get totalCostWithTravel =>
      (subtotalCents + additionalCostCents) / 100.0;
  double? get netSavingsAfterTravel => null;
  double get packCost =>
      (purchase.netAmountCents /
          (purchase.quantity > 0 ? purchase.quantity : 1)) /
      100.0;

  double get subtotal => subtotalCents / 100.0;
  double get totalWithFare => (subtotalCents + additionalCostCents) / 100.0;
  double get unitCost => purchase.costPerPieceCents / 100.0;
  String get supplierName => purchase.supplier.name;
  int get piecesPerPack => purchase.piecesPerPack;
  String get supplierId => purchase.supplier.id;
}

typedef RestockSupplierOption = RestockSupplierEstimate;

class RestockEstimate {
  const RestockEstimate({
    this.product,
    required this.targetPieces,
    List<RestockSupplierEstimate>? suppliers,
    List<RestockSupplierEstimate>? estimates,
    this.additionalCostCents = 0,
  }) : suppliers = suppliers ?? estimates ?? const [];

  final Product? product;
  final int targetPieces;
  final List<RestockSupplierEstimate> suppliers;
  final int additionalCostCents;

  List<RestockSupplierEstimate> get estimates => suppliers;
  List<RestockSupplierOption> get supplierOptions => suppliers;
  RestockSupplierOption? get recommendedSupplier =>
      suppliers.isNotEmpty ? suppliers.first : null;
}

class BasketItem {
  const BasketItem({required this.product, required this.estimate});
  final Product product;
  final RestockSupplierEstimate estimate;

  int get pieces => estimate.targetPieces;
  int get packs => estimate.packsToBuy;
  double get cost => estimate.subtotal;
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

  double get totalCost => totalCents / 100.0;
  double get subtotalCost => subtotalCents / 100.0;
  double get travelCost => additionalCostCents / 100.0;
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
    List<BasketSupplierGroup>? groups,
    List<BasketSupplierGroup>? supplierGroups,
    this.missingProducts = const [],
    this.alternatives = const [],
    int? overallTotalCents,
  }) : groups = groups ?? supplierGroups ?? const [];

  final List<BasketSupplierGroup> groups;
  final List<Product> missingProducts;
  final List<BasketSupplierAlternative> alternatives;

  List<BasketSupplierGroup> get supplierGroups => groups;
  int get subtotalCents =>
      groups.fold(0, (sum, group) => sum + group.subtotalCents);
  int get totalCents => groups.fold(0, (sum, group) => sum + group.totalCents);
  int get overallTotalCents => totalCents;
  double get totalOverallCost => totalCents / 100.0;
}
