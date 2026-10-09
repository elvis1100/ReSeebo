import 'package:flutter/material.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../state/basket_controller.dart';
import 'basket_purchase_row.dart';

class BasketResults extends StatelessWidget {
  const BasketResults({
    super.key,
    required this.controller,
    required this.onReceipt,
  });
  final BasketController controller;
  final ValueChanged<String> onReceipt;

  @override
  Widget build(BuildContext context) {
    final estimate = controller.estimate!;
    final best = controller.bestCompleteAlternative;
    final savings = controller.completeAlternativeSavings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Buying estimate',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Amount(
                estimate.missingProducts.isEmpty
                    ? 'Grouped estimated total'
                    : 'Known estimated total · partial',
                estimate.totalCents,
                bold: true,
              ),
              _Amount(
                estimate.missingProducts.isEmpty
                    ? 'Grouped product subtotal'
                    : 'Known product subtotal · partial',
                estimate.subtotalCents,
              ),
              _Amount(
                'Travel / delivery',
                controller.totalAdditionalCostsCents,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Notice(
          message:
              'Products use the lowest subtotal among each supplier’s latest recorded prices. Travel is added once per supplier. Prices are dated estimates; availability is unknown.',
        ),
        if (estimate.missingProducts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Notice(
              message:
                  'No recorded comparable price for: ${estimate.missingProducts.map((product) => '${product.name} (${product.identity})').join('; ')}. Totals cover known products only.',
              warning: true,
            ),
          ),
        if (best != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lowest complete single-supplier total',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(best.supplier.label),
                  CurrencyText(
                    cents: best.knownTotalCents,
                    suffix: ' including extra cost',
                  ),
                  if (savings != null)
                    CurrencyText(
                      cents: savings.abs(),
                      prefix: savings >= 0
                          ? 'Savings vs grouped total: '
                          : 'Extra cost vs grouped total: ',
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.xl),
        Text('Buying groups', style: Theme.of(context).textTheme.titleLarge),
        for (final group in estimate.groups)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.supplier.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  _Amount('Supplier total', group.totalCents, bold: true),
                  _Amount('Product subtotal', group.subtotalCents),
                  _Amount(
                    'Travel / delivery · once',
                    group.additionalCostCents,
                  ),
                  _RecordedDetails(items: group.items, onReceipt: onReceipt),
                ],
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Single-supplier alternatives',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Missing product prices stay unknown. Partial totals cannot be compared as complete baskets.',
          style: TextStyle(color: AppColors.muted),
        ),
        for (final alternative in estimate.alternatives)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alternative.supplier.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    alternative.missingProducts.isEmpty
                        ? 'Complete recorded basket'
                        : 'Partial basket · ${alternative.missingProducts.length} unknown prices',
                    style: TextStyle(
                      color: alternative.missingProducts.isEmpty
                          ? AppColors.primary
                          : AppColors.amberText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  _Amount(
                    alternative.missingProducts.isEmpty
                        ? 'Estimated total'
                        : 'Known estimated total · partial',
                    alternative.knownTotalCents,
                    bold: true,
                  ),
                  _Amount(
                    alternative.missingProducts.isEmpty
                        ? 'Product subtotal'
                        : 'Known product subtotal · partial',
                    alternative.knownSubtotalCents,
                  ),
                  _Amount(
                    'Travel / delivery · once',
                    alternative.additionalCostCents,
                  ),
                  for (final product in alternative.missingProducts)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        '${product.name} · ${product.identity}\nPrice unknown',
                        style: const TextStyle(color: AppColors.amberText),
                      ),
                    ),
                  if (alternative.items.isNotEmpty)
                    _RecordedDetails(
                      items: alternative.items,
                      onReceipt: onReceipt,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RecordedDetails extends StatelessWidget {
  const _RecordedDetails({required this.items, required this.onReceipt});
  final List<BasketItem> items;
  final ValueChanged<String> onReceipt;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    childrenPadding: EdgeInsets.zero,
    title: Text('Recorded product details (${items.length})'),
    children: [
      for (final item in items)
        BasketPurchaseRow(item: item, onReceipt: onReceipt),
    ],
  );
}

class _Amount extends StatelessWidget {
  const _Amount(this.label, this.cents, {this.bold = false});
  final String label;
  final int cents;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        Text('$label:'),
        CurrencyText(
          cents: cents,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}
