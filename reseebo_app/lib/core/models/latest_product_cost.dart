/// Dashboard summary in centavos per individual piece, retaining fractional
/// centavos rather than rounding a historical unit cost.
class LatestProductCost {
  const LatestProductCost({
    required this.costPerPieceCents,
    required this.purchasedAt,
  });

  final double costPerPieceCents;
  final DateTime purchasedAt;
}
