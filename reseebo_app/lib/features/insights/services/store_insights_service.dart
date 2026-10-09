import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../models/store_insights.dart';

class StoreInsightsService {
  const StoreInsightsService(this.adapter);
  final IReseeboDataAdapter adapter;

  Future<List<ProductComparisonData>> load() async {
    final products = await adapter.getProducts();
    final comparisons = <ProductComparisonData>[];
    for (final product in products) {
      comparisons.add(await adapter.getProductComparison(product.id));
    }
    return comparisons;
  }

  /// Summary periods use local calendar purchase dates. Supplier alternatives
  /// remain latest recorded prices across all history, independent of period.
  static StoreInsights summarize(
    List<ProductComparisonData> data,
    InsightPeriod period,
    DateTime now,
  ) {
    final local = now.toLocal();
    final today = DateTime(local.year, local.month, local.day);
    final end = DateTime(today.year, today.month, today.day + 1);
    final start = switch (period) {
      InsightPeriod.last30Days => DateTime(
        today.year,
        today.month,
        today.day - 29,
      ),
      InsightPeriod.thisMonth => DateTime(today.year, today.month),
      InsightPeriod.allHistory => null,
    };
    var spent = 0;
    final receipts = <String>{};
    final suppliers = <String>{};
    final seenLines = <String>{};
    final changes = <ProductPriceChange>[];
    for (final comparison in data) {
      for (final row in comparison.history) {
        final purchase = row.purchase;
        final date = purchase.purchasedAt.toLocal();
        if (date.isBefore(end) &&
            (start == null || !date.isBefore(start)) &&
            seenLines.add(purchase.id)) {
          spent += purchase.netAmountCents;
          receipts.add(purchase.receiptId);
          suppliers.add(purchase.supplier.id);
          if (row.changeCents != null && row.changeCents != 0) {
            changes.add(ProductPriceChange(comparison.product, row));
          }
        }
      }
    }
    changes.sort((a, b) => b.history.date.compareTo(a.history.date));
    final alternatives =
        data.where((entry) => entry.latestPrices.isNotEmpty).toList()..sort(
          (a, b) => a.product.displayTitle.compareTo(b.product.displayTitle),
        );
    return StoreInsights(
      spentCents: spent,
      receiptCount: receipts.length,
      supplierCount: suppliers.length,
      changes: changes,
      comparisons: alternatives,
    );
  }
}
