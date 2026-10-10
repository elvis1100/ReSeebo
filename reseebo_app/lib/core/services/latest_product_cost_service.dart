import '../models/latest_product_cost.dart';
import '../models/models.dart';

/// Applies the dashboard ordering to already-selected supplier latest prices.
/// Storage adapters can implement the same contract directly in their query.
/// Across suppliers, initial recorded time precedes receipt order and line
/// sequence; corrections cannot make new rows appear to be newly saved receipts.
LatestProductCost? latestProductCost(List<PurchaseRecord> supplierLatest) {
  if (supplierLatest.isEmpty) return null;
  DateTime day(DateTime date) => DateTime(date.year, date.month, date.day);
  final incompleteDays = supplierLatest
      .where((purchase) => !purchase.hasPurchaseTime)
      .map((purchase) => day(purchase.purchasedAt))
      .toSet();
  final sorted = List<PurchaseRecord>.of(supplierLatest)
    ..sort((a, b) {
      final dayA = day(a.purchasedAt);
      final byDate = day(b.purchasedAt).compareTo(dayA);
      if (byDate != 0) return byDate;
      if (!incompleteDays.contains(dayA)) {
        final byTime = b.purchasedAt.compareTo(a.purchasedAt);
        if (byTime != 0) return byTime;
      }
      final byRecorded = b.recordedAt.compareTo(a.recordedAt);
      if (byRecorded != 0) return byRecorded;
      if (a.recordedOrder > 0 && b.recordedOrder > 0) {
        final byReceipt = b.recordedOrder.compareTo(a.recordedOrder);
        if (byReceipt != 0) return byReceipt;
      }
      return b.sequence.compareTo(a.sequence);
    });
  return LatestProductCost(
    costPerPieceCents: sorted.first.costPerPieceCents,
    purchasedAt: sorted.first.purchasedAt,
  );
}
