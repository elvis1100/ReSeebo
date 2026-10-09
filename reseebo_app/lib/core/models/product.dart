/// Represents a confirmed product in the sari-sari store catalog.
class Product {
  final String id;
  final String name;
  final String brand;
  final String variant;
  final String sizeUnit;
  final String? category;
  final String? barcode;
  final String? photoPath;
  final double? markupPercentageOverride;
  final double? ownerSetSellingPrice;

  const Product({
    required this.id,
    required this.name,
    required this.brand,
    required this.variant,
    required this.sizeUnit,
    this.category,
    this.barcode,
    this.photoPath,
    this.markupPercentageOverride,
    this.ownerSetSellingPrice,
  });

  /// Full formatted display name e.g. "Brand X Original Coffee 26g"
  String get displayTitle => '$brand $variant $sizeUnit'.trim();
  String get displayName => displayTitle;

  Product copyWith({
    String? id,
    String? name,
    String? brand,
    String? variant,
    String? sizeUnit,
    String? category,
    String? barcode,
    String? photoPath,
    double? markupPercentageOverride,
    double? ownerSetSellingPrice,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      variant: variant ?? this.variant,
      sizeUnit: sizeUnit ?? this.sizeUnit,
      category: category ?? this.category,
      barcode: barcode ?? this.barcode,
      photoPath: photoPath ?? this.photoPath,
      markupPercentageOverride:
          markupPercentageOverride ?? this.markupPercentageOverride,
      ownerSetSellingPrice: ownerSetSellingPrice ?? this.ownerSetSellingPrice,
    );
  }
}

/// Suggested product match derived from previously confirmed Product Aliases.
class ProductMatchSuggestion {
  final Product product;
  final double confidence;
  final String matchedAlias;
  final bool isAmbiguous;

  const ProductMatchSuggestion({
    required this.product,
    required this.confidence,
    required this.matchedAlias,
    this.isAmbiguous = false,
  });
}
