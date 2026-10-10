import '../errors/app_exception.dart';
import '../models/models.dart';

class PricingService {
  static void validateMarkup(double? value) {
    if (value != null && (!value.isFinite || value < 0 || value > 10000)) {
      throw const ValidationException('Markup must be between 0% and 10,000%.');
    }
  }

  static void validateMoney(int value, {bool allowZero = true}) {
    if (value < (allowZero ? 0 : 1) || value > maxAmountCents) {
      throw const ValidationException(
        'Enter a valid amount within the supported range.',
      );
    }
  }

  static void validateQuantity(int value) {
    if (value <= 0 || value > maxQuantity) {
      throw const ValidationException(
        'Enter a whole quantity between 1 and 1,000,000.',
      );
    }
  }

  static int suggestedSellingPriceCents(
    double costPerPieceCents,
    double markupPercent,
  ) {
    _validateCost(costPerPieceCents);
    validateMarkup(markupPercent);
    final suggested = (costPerPieceCents * (1 + markupPercent / 100)).round();
    validateMoney(suggested);
    return suggested;
  }

  static ProfitCalculation profit(
    double costPerPieceCents,
    int sellingPriceCents,
  ) {
    _validateCost(costPerPieceCents);
    validateMoney(sellingPriceCents);
    final gross = sellingPriceCents - costPerPieceCents;
    return ProfitCalculation(
      costPerPieceCents: costPerPieceCents,
      sellingPriceCents: sellingPriceCents,
      grossProfitCents: gross,
      markupPercent: gross / costPerPieceCents * 100,
      marginPercent: sellingPriceCents == 0
          ? null
          : gross / sellingPriceCents * 100,
    );
  }

  static void _validateCost(double value) {
    if (!value.isFinite || value <= 0 || value > maxAmountCents) {
      throw const ValidationException(
        'A confirmed positive purchase cost is required.',
      );
    }
  }

  /// Whole-pack purchase costs come from the recorded net pack price, not a
  /// rounded cost-per-piece display. Half a centavo rounds up only at payment.
  static RestockSupplierEstimate estimatePurchase(
    PurchaseRecord purchase,
    int targetPieces, {
    int additionalCostCents = 0,
  }) {
    validateQuantity(targetPieces);
    validateMoney(additionalCostCents);
    validateQuantity(purchase.quantity);
    validateQuantity(purchase.piecesPerPack);
    validateMoney(purchase.netAmountCents, allowZero: false);
    final packs =
        (targetPieces + purchase.piecesPerPack - 1) ~/ purchase.piecesPerPack;
    final numerator = BigInt.from(purchase.netAmountCents) * BigInt.from(packs);
    final denominator = BigInt.from(purchase.quantity);
    final subtotal =
        ((numerator * BigInt.two + denominator) ~/ (denominator * BigInt.two))
            .toInt();
    validateMoney(subtotal);
    validateMoney(subtotal + additionalCostCents);
    return RestockSupplierEstimate(
      purchase: purchase,
      targetPieces: targetPieces,
      packsToBuy: packs,
      purchasedPieces: packs * purchase.piecesPerPack,
      subtotalCents: subtotal,
      additionalCostCents: additionalCostCents,
    );
  }

  static int compareUnitCosts(PurchaseRecord a, PurchaseRecord b) =>
      (BigInt.from(a.netAmountCents) * BigInt.from(b.totalPieces)).compareTo(
        BigInt.from(b.netAmountCents) * BigInt.from(a.totalPieces),
      );

  static ProductComparisonData comparison(
    Product product,
    StoreProfile profile,
    List<PurchaseRecord> purchases,
  ) {
    final bySupplier = <String, List<PurchaseRecord>>{};
    for (final purchase in purchases) {
      bySupplier.putIfAbsent(purchase.supplier.id, () => []).add(purchase);
    }
    final latest = <PurchaseRecord>[];
    final history = <PriceHistoryRecord>[];
    for (final supplierPurchases in bySupplier.values) {
      final byDate = <String, List<PurchaseRecord>>{};
      for (final purchase in supplierPurchases) {
        byDate
            .putIfAbsent(_dateKey(purchase.purchasedAt), () => [])
            .add(purchase);
      }
      final days = byDate.keys.toList()..sort();
      PurchaseRecord? previous;
      for (final day in days) {
        final dayPurchases = byDate[day]!;
        final ambiguous =
            dayPurchases.length > 1 &&
            dayPurchases.any((purchase) => !purchase.hasPurchaseTime);
        dayPurchases.sort((a, b) {
          final byTime = ambiguous ? 0 : a.purchasedAt.compareTo(b.purchasedAt);
          if (byTime != 0) return byTime;
          // Initial receipt order is stable even when the clock is corrected
          // or a correction adds lines with later SQLite sequences.
          if (a.recordedOrder > 0 && b.recordedOrder > 0) {
            final byReceipt = a.recordedOrder.compareTo(b.recordedOrder);
            if (byReceipt != 0) return byReceipt;
          }
          final bySequence = a.sequence.compareTo(b.sequence);
          return bySequence != 0
              ? bySequence
              : a.recordedAt.compareTo(b.recordedAt);
        });
        for (final purchase in dayPurchases) {
          history.add(
            PriceHistoryRecord(
              purchase: purchase,
              previousCostPerPieceCents: previous?.costPerPieceCents,
              orderingNote: ambiguous
                  ? 'Purchase times are incomplete on this date. Same-day records use the order they were saved.'
                  : dayPurchases
                            .where(
                              (other) =>
                                  other.purchasedAt == purchase.purchasedAt,
                            )
                            .length >
                        1
                  ? 'Receipts share the same purchase time. Tied records use the order they were saved.'
                  : null,
            ),
          );
          previous = purchase;
        }
      }
      if (previous != null) latest.add(previous);
    }
    latest.sort((a, b) {
      final price = compareUnitCosts(a, b);
      return price != 0 ? price : a.supplier.label.compareTo(b.supplier.label);
    });
    final minimum = latest.isEmpty ? 0.0 : latest.first.costPerPieceCents;
    final historical = List<PurchaseRecord>.of(purchases)
      ..sort(compareUnitCosts);
    return ProductComparisonData(
      product: product,
      profile: profile,
      latestPrices: latest
          .map(
            (purchase) => SupplierPriceRow(
              purchase: purchase,
              bestCostPerPieceCents: minimum,
            ),
          )
          .toList(),
      history: history,
      lowestHistorical: historical.isEmpty ? null : historical.first,
    );
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// Selection minimizes known item subtotals. Supplier extras are grouped once
  /// and shown separately; alternatives expose incomplete price coverage.
  static BasketEstimate basket(
    Map<Product, RestockEstimate> estimates, {
    Map<String, int> additionalCostsCents = const {},
    Iterable<Supplier> knownSuppliers = const [],
  }) {
    for (final extra in additionalCostsCents.values) {
      validateMoney(extra);
    }
    if (estimates.isEmpty) {
      return const BasketEstimate(
        groups: [],
        missingProducts: [],
        alternatives: [],
      );
    }
    final selected = <String, List<BasketItem>>{};
    final suppliers = <String, Supplier>{
      for (final supplier in knownSuppliers) supplier.id: supplier,
    };
    final missing = <Product>[];
    for (final entry in estimates.entries) {
      final candidates = List<RestockSupplierEstimate>.of(entry.value.suppliers)
        ..sort((a, b) {
          final price = a.subtotalCents.compareTo(b.subtotalCents);
          return price != 0
              ? price
              : a.purchase.supplier.label.compareTo(b.purchase.supplier.label);
        });
      for (final candidate in candidates) {
        suppliers[candidate.purchase.supplier.id] = candidate.purchase.supplier;
      }
      if (candidates.isEmpty) {
        missing.add(entry.key);
      } else {
        final cheapest = candidates.first;
        selected
            .putIfAbsent(cheapest.purchase.supplier.id, () => [])
            .add(BasketItem(product: entry.key, estimate: cheapest));
      }
    }
    final groups = <BasketSupplierGroup>[
      for (final entry in selected.entries)
        BasketSupplierGroup(
          supplier: suppliers[entry.key]!,
          items: entry.value,
          additionalCostCents: additionalCostsCents[entry.key] ?? 0,
        ),
    ]..sort((a, b) => a.supplier.label.compareTo(b.supplier.label));
    final alternatives = <BasketSupplierAlternative>[];
    for (final supplier in suppliers.values) {
      final items = <BasketItem>[];
      final missingProducts = <Product>[];
      for (final entry in estimates.entries) {
        final available = entry.value.suppliers
            .where((estimate) => estimate.purchase.supplier.id == supplier.id)
            .toList();
        if (available.isEmpty) {
          missingProducts.add(entry.key);
        } else {
          items.add(BasketItem(product: entry.key, estimate: available.first));
        }
      }
      alternatives.add(
        BasketSupplierAlternative(
          supplier: supplier,
          items: items,
          missingProducts: missingProducts,
          additionalCostCents: additionalCostsCents[supplier.id] ?? 0,
        ),
      );
    }
    alternatives.sort((a, b) => a.supplier.label.compareTo(b.supplier.label));
    final result = BasketEstimate(
      groups: groups,
      missingProducts: missing,
      alternatives: alternatives,
    );
    validateMoney(result.totalCents);
    for (final alternative in alternatives) {
      validateMoney(alternative.knownTotalCents);
    }
    return result;
  }
}
