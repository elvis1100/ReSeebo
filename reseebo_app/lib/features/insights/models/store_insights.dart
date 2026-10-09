import '../../../core/models/models.dart';

enum InsightPeriod { last30Days, thisMonth, allHistory }

class ProductPriceChange {
  const ProductPriceChange(this.product, this.history);
  final Product product;
  final PriceHistoryRecord history;
}

class StoreInsights {
  const StoreInsights({
    required this.spentCents,
    required this.receiptCount,
    required this.supplierCount,
    required this.changes,
    required this.comparisons,
  });
  final int spentCents;
  final int receiptCount;
  final int supplierCount;
  final List<ProductPriceChange> changes;
  final List<ProductComparisonData> comparisons;
}
