import 'dart:math';
import '../models/store_profile.dart';
import '../models/product.dart';
import '../models/supplier.dart';
import '../models/receipt.dart';
import '../models/purchase_line.dart';
import '../models/comparison.dart';
import '../models/restock_estimate.dart';
import 'reseebo_data_adapter.dart';

/// In-memory mock adapter pre-loaded with realistic sari-sari store fixtures.
/// Enables immediate, offline frontend prototyping and UI verification.
class MockReseeboDataAdapter implements IReseeboDataAdapter {
  StoreProfile _profile = const StoreProfile(
    id: 'store_1',
    storeName: "Aling Nena's Sari-Sari Store",
    ownerName: 'Elena Santos',
    defaultMarkupPercentage: 20.0,
  );

  final List<Supplier> _suppliers = [
    const Supplier(
      id: 'sup_a',
      name: 'Puregold Price Club',
      branchLocation: 'Branch A - San Juan',
      notes: 'Near public market',
    ),
    const Supplier(
      id: 'sup_b',
      name: 'Supermarket B (Megamart)',
      branchLocation: 'Highway Branch',
      notes: 'Wholesale packs available',
    ),
    const Supplier(
      id: 'sup_c',
      name: 'Wholesaler C',
      branchLocation: 'Town Proper',
      notes: 'Cash only, discounts on 5+ boxes',
    ),
  ];

  final List<Product> _products = [
    const Product(
      id: 'prod_coffee_26g',
      name: 'Brand X Original Coffee 26g',
      brand: 'Brand X',
      variant: 'Original Coffee',
      sizeUnit: '26g',
      category: 'Beverages',
      barcode: '4800016622114',
      markupPercentageOverride: null, // Uses store default (20%)
      ownerSetSellingPrice: 10.0,
    ),
    const Product(
      id: 'prod_milk_33g',
      name: 'Bear Brand Fortified Milk 33g',
      brand: 'Bear Brand',
      variant: 'Fortified Powdered Milk',
      sizeUnit: '33g',
      category: 'Dairy',
      barcode: '4800361280312',
      markupPercentageOverride: 25.0,
      ownerSetSellingPrice: 16.0,
    ),
    const Product(
      id: 'prod_soysauce_385ml',
      name: 'Silver Swan Soy Sauce 385ml',
      brand: 'Silver Swan',
      variant: 'Soy Sauce Bottle',
      sizeUnit: '385ml',
      category: 'Condiments',
      barcode: '4801011100344',
      markupPercentageOverride: 15.0,
      ownerSetSellingPrice: 22.0,
    ),
    const Product(
      id: 'prod_pancit_60g',
      name: 'Lucky Me! Pancit Canton 60g',
      brand: 'Lucky Me!',
      variant: 'Original Flavor',
      sizeUnit: '60g',
      category: 'Instant Noodles',
      barcode: '4807770270014',
      markupPercentageOverride: null,
      ownerSetSellingPrice: 15.0,
    ),
  ];

  final List<Receipt> _receipts = [
    Receipt(
      id: 'rec_001',
      supplierId: 'sup_a',
      purchaseDate: DateTime(2026, 10, 8),
      localImagePath: 'assets/placeholders/sample_receipt_1.png',
      recordedTimestamp: DateTime(2026, 10, 8, 14, 30),
      receiptNumber: 'OR-89211',
      totalAmount: 168.0,
      itemCount: 1,
    ),
    Receipt(
      id: 'rec_002',
      supplierId: 'sup_c',
      purchaseDate: DateTime(2026, 10, 7),
      localImagePath: 'assets/placeholders/sample_receipt_2.png',
      recordedTimestamp: DateTime(2026, 10, 7, 10, 15),
      receiptNumber: 'SI-44120',
      totalAmount: 245.0,
      itemCount: 2,
    ),
    Receipt(
      id: 'rec_003',
      supplierId: 'sup_b',
      purchaseDate: DateTime(2026, 10, 5),
      localImagePath: 'assets/placeholders/sample_receipt_3.png',
      recordedTimestamp: DateTime(2026, 10, 5, 16, 45),
      receiptNumber: 'INV-1092',
      totalAmount: 78.0,
      itemCount: 1,
    ),
    Receipt(
      id: 'rec_004',
      supplierId: 'sup_a',
      purchaseDate: DateTime(2026, 10, 1),
      localImagePath: 'assets/placeholders/sample_receipt_4.png',
      recordedTimestamp: DateTime(2026, 10, 1, 9, 0),
      receiptNumber: 'OR-81102',
      totalAmount: 80.0,
      itemCount: 1,
    ),
  ];

  @override
  Future<StoreProfile> getStoreProfile() async {
    return _profile;
  }

  @override
  Future<void> updateStoreProfile(StoreProfile profile) async {
    _profile = profile;
  }

  @override
  Future<List<Product>> getProducts({String? query}) async {
    if (query == null || query.trim().isEmpty) {
      return List.unmodifiable(_products);
    }
    final q = query.toLowerCase();
    return _products.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.brand.toLowerCase().contains(q) ||
          p.variant.toLowerCase().contains(q) ||
          (p.barcode != null && p.barcode!.contains(q));
    }).toList();
  }

  @override
  Future<Product?> getProductById(String id) async {
    try {
      return _products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveProduct(Product product) async {
    final index = _products.indexWhere((p) => p.id == product.id);
    if (index >= 0) {
      _products[index] = product;
    } else {
      _products.add(product);
    }
  }

  @override
  Future<List<ProductMatchSuggestion>> matchAliases(
      String rawOcrDescription) async {
    final lower = rawOcrDescription.toLowerCase();
    final suggestions = <ProductMatchSuggestion>[];

    for (final p in _products) {
      if (lower.contains(p.brand.toLowerCase()) ||
          lower.contains(p.variant.toLowerCase().split(' ').first)) {
        suggestions.add(ProductMatchSuggestion(
          product: p,
          confidence: 0.88,
          matchedAlias: rawOcrDescription,
          isAmbiguous: false,
        ));
      }
    }

    if (suggestions.isEmpty && _products.isNotEmpty) {
      suggestions.add(ProductMatchSuggestion(
        product: _products.first,
        confidence: 0.45,
        matchedAlias: 'Unconfirmed Match',
        isAmbiguous: true,
      ));
    }

    return suggestions;
  }

  @override
  Future<List<Supplier>> getSuppliers() async => List.unmodifiable(_suppliers);

  @override
  Future<Supplier?> getSupplierById(String id) async {
    try {
      return _suppliers.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveSupplier(Supplier supplier) async {
    final index = _suppliers.indexWhere((s) => s.id == supplier.id);
    if (index >= 0) {
      _suppliers[index] = supplier;
    } else {
      _suppliers.add(supplier);
    }
  }

  @override
  Future<List<Receipt>> getRecentReceipts({int limit = 20}) async {
    final sorted = List<Receipt>.from(_receipts)
      ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
    return sorted.take(limit).toList();
  }

  @override
  Future<ReceiptDraft> processReceiptImage(String localImagePath) async {
    // Simulates on-device OCR extraction
    return ReceiptDraft(
      localImagePath: localImagePath,
      supplierId: 'sup_a',
      supplierName: 'Puregold Price Club',
      branchLocation: 'Branch A - San Juan',
      purchaseDate: DateTime(2026, 10, 8),
      receiptNumber: 'OR-${Random().nextInt(90000) + 10000}',
      lines: [
        ParsedLineItem(
          tempId: 'line_1',
          rawDescription: 'BRANDX COF ORIG 26G',
          matchedProductId: 'prod_coffee_26g',
          quantity: 2.0,
          unitType: 'pack',
          piecesPerPack: 10,
          netAmount: 168.0,
          discount: 0.0,
          isAmbiguous: false,
        ),
        ParsedLineItem(
          tempId: 'line_2',
          rawDescription: 'BEAR BRND PWDR 33G',
          matchedProductId: 'prod_milk_33g',
          quantity: 1.0,
          unitType: 'pack',
          piecesPerPack: 12,
          netAmount: 156.0,
          discount: 0.0,
          isAmbiguous: true,
        ),
      ],
    );
  }

  @override
  Future<SaveReceiptResult> saveConfirmedReceipt(
      ReceiptDraft confirmedDraft) async {
    final newId = 'rec_${DateTime.now().millisecondsSinceEpoch}';
    final receipt = Receipt(
      id: newId,
      supplierId: confirmedDraft.supplierId ?? 'sup_a',
      purchaseDate: confirmedDraft.purchaseDate,
      localImagePath: confirmedDraft.localImagePath,
      recordedTimestamp: DateTime.now(),
      receiptNumber: confirmedDraft.receiptNumber,
      notes: confirmedDraft.notes,
      totalAmount: confirmedDraft.totalAmount,
      itemCount: confirmedDraft.lines.length,
    );
    _receipts.insert(0, receipt);
    return SaveReceiptResult(
      receiptId: newId,
      lineIds: confirmedDraft.lines.map((l) => l.tempId).toList(),
    );
  }

  @override
  Future<ProductComparisonData> getProductComparison(String productId) async {
    final product = await getProductById(productId) ?? _products.first;

    // Realistic multi-supplier comparison rows matching SARI-SARI-RECEIPT-IDEA.md
    final supplierRows = [
      const SupplierPriceRow(
        supplierId: 'sup_b',
        supplierName: 'Supermarket B (Megamart)',
        branchLocation: 'Highway Branch',
        latestPurchaseDate: _ConstDate(2026, 10, 5),
        packageDescription: '1 pack × 10 sachets',
        netAmountPaid: 78.0,
        costPerPiece: 7.80,
        differenceVsBest: 0.0,
        isLowestPrice: true,
        sourceReceiptId: 'rec_003',
      ),
      const SupplierPriceRow(
        supplierId: 'sup_c',
        supplierName: 'Wholesaler C',
        branchLocation: 'Town Proper',
        latestPurchaseDate: _ConstDate(2026, 10, 7),
        packageDescription: '1 pack × 10 sachets',
        netAmountPaid: 81.0,
        costPerPiece: 8.10,
        differenceVsBest: 0.30,
        isLowestPrice: false,
        sourceReceiptId: 'rec_002',
      ),
      const SupplierPriceRow(
        supplierId: 'sup_a',
        supplierName: 'Puregold Price Club',
        branchLocation: 'Branch A - San Juan',
        latestPurchaseDate: _ConstDate(2026, 10, 8),
        packageDescription: '2 packs × 10 sachets',
        netAmountPaid: 168.0,
        costPerPiece: 8.40,
        differenceVsBest: 0.60,
        isLowestPrice: false,
        sourceReceiptId: 'rec_001',
      ),
    ];

    // Price history at Supplier A showing price hike from ₱8.00 to ₱8.40 (+5%)
    final historyRows = [
      const PriceHistoryRecord(
        purchaseDate: _ConstDate(2026, 10, 8),
        costPerPiece: 8.40,
        changeFromPreviousPesos: 0.40,
        changeFromPreviousPercent: 5.0,
        packageDetails: '2 packs × 10 sachets (₱168.00)',
        sourceReceiptId: 'rec_001',
      ),
      const PriceHistoryRecord(
        purchaseDate: _ConstDate(2026, 10, 1),
        costPerPiece: 8.00,
        changeFromPreviousPesos: null,
        changeFromPreviousPercent: null,
        packageDetails: '1 pack × 10 sachets (₱80.00)',
        sourceReceiptId: 'rec_004',
      ),
    ];

    return ProductComparisonData(
      product: product,
      supplierRows: supplierRows,
      historyRows: historyRows,
      lowestHistoricalPrice: 7.80,
      lowestHistoricalDate: DateTime(2026, 10, 5),
      lowestHistoricalSupplierName: 'Supermarket B',
    );
  }

  @override
  Future<RestockEstimate> calculateRestock({
    required String productId,
    required int targetPieces,
    required double additionalCost,
  }) async {
    // Calculates restock options rounding UP (ceil) to whole packs
    // Options: Supplier B (pack of 10 @ ₱78), Supplier A (pack of 10 @ ₱84)
    const piecesPerPack = 10;
    final packsNeeded = (targetPieces / piecesPerPack).ceil();
    final actualPieces = packsNeeded * piecesPerPack;

    // Supplier B
    final costB = packsNeeded * 78.0;
    final totalWithTravelB = costB + additionalCost;

    // Supplier A
    final costA = packsNeeded * 84.0;
    const travelCostA = 0.0; // Near public market / no travel
    final totalWithTravelA = costA + travelCostA;

    final grossSavings = costA - costB;
    final netSavings = totalWithTravelA - totalWithTravelB;

    return RestockEstimate(
      productId: productId,
      targetPieces: targetPieces,
      supplierOptions: [
        RestockSupplierOption(
          supplierId: 'sup_b',
          supplierName: 'Supermarket B',
          priceDate: DateTime(2026, 10, 5),
          piecesPerPack: piecesPerPack,
          packCost: 78.0,
          packsNeeded: packsNeeded,
          totalPiecesPurchased: actualPieces,
          totalPurchaseCost: costB,
          travelCost: additionalCost,
          totalCostWithTravel: totalWithTravelB,
          grossSavingsVsAlternate: grossSavings,
          netSavingsAfterTravel: netSavings,
        ),
        RestockSupplierOption(
          supplierId: 'sup_a',
          supplierName: 'Puregold Branch A',
          priceDate: DateTime(2026, 10, 8),
          piecesPerPack: piecesPerPack,
          packCost: 84.0,
          packsNeeded: packsNeeded,
          totalPiecesPurchased: actualPieces,
          totalPurchaseCost: costA,
          travelCost: 0.0,
          totalCostWithTravel: totalWithTravelA,
          grossSavingsVsAlternate: 0.0,
          netSavingsAfterTravel: 0.0,
        ),
      ],
    );
  }

  @override
  Future<ProfitCalculation> calculateProfit({
    required String productId,
    required double costPerPiece,
    double? customMarkupPercentage,
    double? customSellingPrice,
  }) async {
    final product = await getProductById(productId);
    final markup = customMarkupPercentage ??
        product?.markupPercentageOverride ??
        _profile.defaultMarkupPercentage;

    return ProfitCalculation.compute(
      costPerPiece: costPerPiece,
      markupPercentage: markup,
      isProductOverride: product?.markupPercentageOverride != null,
      ownerSetSellingPrice: customSellingPrice ?? product?.ownerSetSellingPrice,
    );
  }
}

class _ConstDate implements DateTime {
  final int _year;
  final int _month;
  final int _day;

  const _ConstDate(this._year, this._month, this._day);

  @override
  int get year => _year;
  @override
  int get month => _month;
  @override
  int get day => _day;
  @override
  int get hour => 0;
  @override
  int get minute => 0;
  @override
  int get second => 0;
  @override
  int get millisecond => 0;
  @override
  int get microsecond => 0;
  @override
  bool get isUtc => false;

  @override
  DateTime add(Duration duration) => DateTime(_year, _month, _day).add(duration);
  @override
  DateTime subtract(Duration duration) => DateTime(_year, _month, _day).subtract(duration);
  @override
  Duration difference(DateTime other) => DateTime(_year, _month, _day).difference(other);
  @override
  int compareTo(DateTime other) => DateTime(_year, _month, _day).compareTo(other);
  @override
  bool isAfter(DateTime other) => DateTime(_year, _month, _day).isAfter(other);
  @override
  bool isBefore(DateTime other) => DateTime(_year, _month, _day).isBefore(other);
  @override
  bool isAtSameMomentAs(DateTime other) => DateTime(_year, _month, _day).isAtSameMomentAs(other);
  @override
  String toIso8601String() => DateTime(_year, _month, _day).toIso8601String();
  @override
  DateTime toLocal() => DateTime(_year, _month, _day);
  @override
  DateTime toUtc() => DateTime(_year, _month, _day).toUtc();
  @override
  String get timeZoneName => DateTime(_year, _month, _day).timeZoneName;
  @override
  Duration get timeZoneOffset => DateTime(_year, _month, _day).timeZoneOffset;
  @override
  int get weekday => DateTime(_year, _month, _day).weekday;
  @override
  int get millisecondsSinceEpoch => DateTime(_year, _month, _day).millisecondsSinceEpoch;
  @override
  int get microsecondsSinceEpoch => DateTime(_year, _month, _day).microsecondsSinceEpoch;
}
