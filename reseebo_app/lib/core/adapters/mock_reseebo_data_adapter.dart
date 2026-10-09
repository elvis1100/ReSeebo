import 'dart:math';
import '../services/latest_product_cost_service.dart';
import '../services/pricing_service.dart';
import 'i_reseebo_data_adapter.dart';

/// In-memory mock adapter pre-loaded with realistic sari-sari store fixtures.
/// Enables immediate, offline frontend prototyping and lightweight Web testing.
class MockReseeboDataAdapter implements IReseeboDataAdapter {
  StoreProfile _profile = const StoreProfile(
    name: "Aling Nena's Sari-Sari Store",
    ownerName: 'Elena Santos',
    defaultMarkupPercent: 20.0,
  );

  final List<Supplier> _suppliers = [
    const Supplier(
      id: 'sup_a',
      name: 'Puregold Price Club',
      branch: 'Branch A - San Juan',
      notes: 'Near public market',
    ),
    const Supplier(
      id: 'sup_b',
      name: 'Supermarket B (Megamart)',
      branch: 'Highway Branch',
      notes: 'Wholesale packs available',
    ),
    const Supplier(
      id: 'sup_c',
      name: 'Wholesaler C',
      branch: 'Town Proper',
      notes: 'Cash only, discounts on 5+ boxes',
    ),
  ];

  final List<Product> _products = [
    const Product(
      id: 'prod_coffee_26g',
      name: 'Brand X Original Coffee 26g',
      brand: 'Brand X',
      variant: 'Original Coffee',
      size: '26g',
      category: 'Beverages',
      barcode: '4800016622114',
      markupPercent: null, // Uses store default (20%)
      sellingPriceCents: 1000,
    ),
    const Product(
      id: 'prod_milk_33g',
      name: 'Bear Brand Fortified Milk 33g',
      brand: 'Bear Brand',
      variant: 'Fortified Powdered Milk',
      size: '33g',
      category: 'Dairy',
      barcode: '4800361280312',
      markupPercent: 25.0,
      sellingPriceCents: 1600,
    ),
    const Product(
      id: 'prod_soysauce_385ml',
      name: 'Silver Swan Soy Sauce 385ml',
      brand: 'Silver Swan',
      variant: 'Soy Sauce Bottle',
      size: '385ml',
      category: 'Condiments',
      barcode: '4801011100344',
      markupPercent: 15.0,
      sellingPriceCents: 2200,
    ),
    const Product(
      id: 'prod_pancit_60g',
      name: 'Lucky Me! Pancit Canton 60g',
      brand: 'Lucky Me!',
      variant: 'Original Flavor',
      size: '60g',
      category: 'Instant Noodles',
      barcode: '4807770270014',
      markupPercent: null,
      sellingPriceCents: 1500,
    ),
  ];

  late final List<Receipt> _receipts;

  MockReseeboDataAdapter() {
    _receipts = [
      Receipt(
        id: 'rec_001',
        supplier: _suppliers[0],
        purchasedAt: DateTime(2026, 10, 8),
        hasPurchaseTime: false,
        createdAt: DateTime(2026, 10, 8, 14, 30),
        imagePath: 'assets/placeholders/sample_receipt_1.png',
        receiptNumber: 'OR-89211',
        totalCents: 16800,
        lineCount: 1,
      ),
      Receipt(
        id: 'rec_002',
        supplier: _suppliers[2],
        purchasedAt: DateTime(2026, 10, 7),
        hasPurchaseTime: false,
        createdAt: DateTime(2026, 10, 7, 10, 15),
        imagePath: 'assets/placeholders/sample_receipt_2.png',
        receiptNumber: 'SI-44120',
        totalCents: 24500,
        lineCount: 2,
      ),
      Receipt(
        id: 'rec_003',
        supplier: _suppliers[1],
        purchasedAt: DateTime(2026, 10, 5),
        hasPurchaseTime: false,
        createdAt: DateTime(2026, 10, 5, 16, 45),
        imagePath: 'assets/placeholders/sample_receipt_3.png',
        receiptNumber: 'INV-1092',
        totalCents: 7800,
        lineCount: 1,
      ),
      Receipt(
        id: 'rec_004',
        supplier: _suppliers[0],
        purchasedAt: DateTime(2026, 10, 1),
        hasPurchaseTime: false,
        createdAt: DateTime(2026, 10, 1, 9, 0),
        imagePath: 'assets/placeholders/sample_receipt_4.png',
        receiptNumber: 'OR-81102',
        totalCents: 8000,
        lineCount: 1,
      ),
    ];
  }

  @override
  Future<StoreProfile> getStoreProfile() async => _profile;

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
          p.variant.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Future<Product?> getProductById(String id) async {
    return _products.where((p) => p.id == id).firstOrNull;
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
    final desc = rawOcrDescription.toLowerCase();
    final suggestions = <ProductMatchSuggestion>[];

    for (final p in _products) {
      if (desc.contains(p.brand.toLowerCase()) ||
          desc.contains(p.variant.toLowerCase().split(' ').first)) {
        suggestions.add(
          ProductMatchSuggestion(
            product: p,
            reason: 'Matched brand/variant from catalog',
            exactAlias: desc.contains(p.brand.toLowerCase()),
          ),
        );
      }
    }
    if (suggestions.isEmpty && _products.isNotEmpty) {
      suggestions.add(
        ProductMatchSuggestion(
          product: _products.first,
          reason: 'Suggested fallback based on recent purchases',
          exactAlias: false,
        ),
      );
    }
    return suggestions;
  }

  @override
  Future<List<ProductAlias>> getAliases(String productId) async => [];

  @override
  Future<void> deleteAlias(String aliasId) async {}

  @override
  Future<List<Supplier>> getSuppliers() async {
    return List.unmodifiable(_suppliers);
  }

  @override
  Future<Supplier?> getSupplierById(String id) async {
    return _suppliers.where((s) => s.id == id).firstOrNull;
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
  Future<List<Receipt>> getRecentReceipts({int limit = 200, String? query}) async {
    var sorted = List<Receipt>.from(_receipts)
      ..sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));
    if (query != null && query.isNotEmpty) {
      sorted = sorted.where((r) => r.supplierName.toLowerCase().contains(query.toLowerCase())).toList();
    }
    return sorted.take(limit).toList();
  }

  @override
  Future<ReceiptDetail> getReceipt(String receiptId) async {
    final r = _receipts.firstWhere((x) => x.id == receiptId);
    return ReceiptDetail(receipt: r, lines: []);
  }

  @override
  Future<ReceiptDraft> processReceiptImage(
    String localImagePath, {
    String? recognitionImagePath,
  }) async {
    return ReceiptDraft(
      imagePath: localImagePath,
      supplierId: 'sup_a',
      supplierName: 'Puregold Price Club',
      supplierBranch: 'Branch A - San Juan',
      purchasedAt: DateTime(2026, 10, 8),
      receiptNumber: 'OR-${Random().nextInt(90000) + 10000}',
      detectedTotalCents: 32400,
      lines: [
        ParsedLineItem(
          id: 'line_1',
          description: 'BRANDX COF ORIG 26G',
          productId: 'prod_coffee_26g',
          quantity: 2,
          unit: PurchaseUnit.pack,
          piecesPerPack: 10,
          grossAmountCents: 16800,
          discountCents: 0,
          confirmed: true,
        ),
        ParsedLineItem(
          id: 'line_2',
          description: 'BEAR BRND PWDR 33G',
          productId: 'prod_milk_33g',
          quantity: 1,
          unit: PurchaseUnit.pack,
          piecesPerPack: 12,
          grossAmountCents: 15600,
          discountCents: 0,
          confirmed: false,
        ),
      ],
    );
  }

  @override
  Future<SaveReceiptResult> saveConfirmedReceipt(
      ReceiptDraft confirmedDraft) async {
    final newId = 'rec_${DateTime.now().millisecondsSinceEpoch}';
    final supplier = _suppliers.firstWhere(
      (s) => s.id == (confirmedDraft.supplierId ?? 'sup_a'),
      orElse: () => _suppliers.first,
    );
    final receipt = Receipt(
      id: newId,
      supplier: supplier,
      purchasedAt: confirmedDraft.purchasedAt ?? DateTime.now(),
      hasPurchaseTime: confirmedDraft.hasPurchaseTime,
      createdAt: DateTime.now(),
      imagePath: confirmedDraft.imagePath,
      receiptNumber: confirmedDraft.receiptNumber,
      notes: confirmedDraft.notes,
      totalCents: confirmedDraft.detectedTotalCents ??
          confirmedDraft.lines.fold<int>(0, (sum, l) => sum + (l.netAmountCents ?? 0)),
      lineCount: confirmedDraft.lines.length,
    );
    _receipts.insert(0, receipt);

    return SaveReceiptResult(
      receiptId: newId,
      lineIds: confirmedDraft.lines.map((l) => l.id).toList(),
      unitCostsCents: confirmedDraft.lines.map((l) => l.costPerPieceCents ?? 0.0).toList(),
      alreadySaved: false,
    );
  }

  @override
  Future<ProductComparisonData> getProductComparison(String productId) async {
    final product = await getProductById(productId) ?? _products.first;

    final pPuregold = PurchaseRecord(
      id: 'pur_1',
      receiptId: 'rec_001',
      productId: product.id,
      supplier: _suppliers[0],
      purchasedAt: DateTime(2026, 10, 8),
      hasPurchaseTime: false,
      recordedAt: DateTime(2026, 10, 8),
      originalDescription: 'Brand X Coffee 26g 10s',
      quantity: 2,
      unit: PurchaseUnit.pack,
      piecesPerPack: 10,
      netAmountCents: 16800,
      imagePath: 'assets/placeholders/sample_receipt_1.png',
    );

    final pMegamart = PurchaseRecord(
      id: 'pur_2',
      receiptId: 'rec_003',
      productId: product.id,
      supplier: _suppliers[1],
      purchasedAt: DateTime(2026, 10, 5),
      hasPurchaseTime: false,
      recordedAt: DateTime(2026, 10, 5),
      originalDescription: 'Brand X Coffee 26g Pack of 10',
      quantity: 1,
      unit: PurchaseUnit.pack,
      piecesPerPack: 10,
      netAmountCents: 8700,
      imagePath: 'assets/placeholders/sample_receipt_3.png',
    );

    final pWholesaler = PurchaseRecord(
      id: 'pur_3',
      receiptId: 'rec_002',
      productId: product.id,
      supplier: _suppliers[2],
      purchasedAt: DateTime(2026, 10, 7),
      hasPurchaseTime: false,
      recordedAt: DateTime(2026, 10, 7),
      originalDescription: 'Brand X 26g Box',
      quantity: 1,
      unit: PurchaseUnit.pack,
      piecesPerPack: 10,
      netAmountCents: 8200,
      imagePath: 'assets/placeholders/sample_receipt_2.png',
    );

    final pHistoricalOld = PurchaseRecord(
      id: 'pur_4',
      receiptId: 'rec_004',
      productId: product.id,
      supplier: _suppliers[0],
      purchasedAt: DateTime(2026, 10, 1),
      hasPurchaseTime: false,
      recordedAt: DateTime(2026, 10, 1),
      originalDescription: 'Brand X Coffee 26g Promo',
      quantity: 1,
      unit: PurchaseUnit.pack,
      piecesPerPack: 10,
      netAmountCents: 8000,
      imagePath: 'assets/placeholders/sample_receipt_4.png',
    );

    return ProductComparisonData(
      product: product,
      profile: _profile,
      latestPrices: [
        SupplierPriceRow(
          purchase: pWholesaler,
          bestCostPerPieceCents: 820.0,
        ),
        SupplierPriceRow(
          purchase: pPuregold,
          bestCostPerPieceCents: 820.0,
        ),
        SupplierPriceRow(
          purchase: pMegamart,
          bestCostPerPieceCents: 820.0,
        ),
      ],
      history: [
        PriceHistoryRecord(
          purchase: pPuregold,
          previousCostPerPieceCents: 800.0,
        ),
        PriceHistoryRecord(
          purchase: pWholesaler,
          previousCostPerPieceCents: null,
        ),
        PriceHistoryRecord(
          purchase: pMegamart,
          previousCostPerPieceCents: null,
        ),
        PriceHistoryRecord(
          purchase: pHistoricalOld,
          previousCostPerPieceCents: null,
        ),
      ],
      lowestHistorical: pHistoricalOld,
    );
  }

  @override
  Future<RestockEstimate> calculateRestock({
    required String productId,
    required int targetPieces,
    required double additionalCost,
    Map<String, int> additionalCostsCents = const {},
  }) async {
    final comparison = await getProductComparison(productId);
    final additionalCents = (additionalCost * 100).round();

    final estimates = comparison.latestPrices.map((row) {
      return PricingService.estimatePurchase(
        row.purchase,
        targetPieces,
        additionalCostCents: additionalCostsCents[row.purchase.supplier.id] ?? additionalCents,
      );
    }).toList();

    return RestockEstimate(
      targetPieces: targetPieces,
      additionalCostCents: additionalCents,
      estimates: estimates,
    );
  }

  @override
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

  @override
  Future<ReceiptDraft> processReceiptImages(
    List<String> localImagePaths, {
    List<String>? recognitionImagePaths,
  }) async {
    return processReceiptImage(
      localImagePaths.first,
      recognitionImagePath: recognitionImagePaths?.firstOrNull,
    );
  }

  @override
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

  @override
  Future<BasketEstimate> calculateBasket(
    Map<String, int> targetPieces, {
    Map<String, int> additionalCostsCents = const {},
  }) async {
    return const BasketEstimate(
      groups: [],
      missingProducts: [],
      alternatives: [],
    );
  }

  @override
  Future<void> close() async {}
}
