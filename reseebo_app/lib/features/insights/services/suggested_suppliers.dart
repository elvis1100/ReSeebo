import '../../../core/models/models.dart';

class SuggestedProduct {
  const SuggestedProduct(this.product, this.price, {required this.tied});
  final Product product;
  final SupplierPriceRow price;
  final bool tied;
}

class SupplierSuggestions {
  const SupplierSuggestions(this.supplier, this.products);
  final Supplier supplier;
  final List<SuggestedProduct> products;
}

/// Uses each supplier's latest price selected by the comparison service, never
/// its historical minimum. Sole-supplier records cannot establish a winner.
List<SupplierSuggestions> suggestedSuppliers(List<ProductComparisonData> comparisons) {
  final groups = <String, List<SuggestedProduct>>{};
  final suppliers = <String, Supplier>{};
  for (final comparison in comparisons) {
    final rows = comparison.latestPrices;
    if (rows.map((row) => row.purchase.supplier.id).toSet().length < 2) continue;
    final lowest = rows.where((row) => row.isLowest).toList();
    for (final row in lowest) {
      final supplier = row.purchase.supplier;
      suppliers[supplier.id] = supplier;
      (groups[supplier.id] ??= []).add(SuggestedProduct(comparison.product, row,
        tied: lowest.length > 1));
    }
  }
  final result = [for (final entry in groups.entries)
    SupplierSuggestions(suppliers[entry.key]!, entry.value..sort((a, b) =>
      a.product.displayTitle.compareTo(b.product.displayTitle)))];
  result.sort((a, b) => a.supplier.displayName.compareTo(b.supplier.displayName));
  return result;
}
