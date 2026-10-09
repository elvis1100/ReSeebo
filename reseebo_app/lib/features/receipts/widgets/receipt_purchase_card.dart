import 'package:flutter/material.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';

class ReceiptPurchaseCard extends StatelessWidget {
  const ReceiptPurchaseCard({
    super.key,
    required this.line,
    this.product,
    required this.onCompare,
  });
  final PurchaseRecord line;
  final Product? product;
  final VoidCallback onCompare;
  @override
  Widget build(BuildContext context) {
    final name = product?.displayName ?? line.originalDescription;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  onPressed: onCompare,
                  tooltip: 'Compare prices',
                  icon: const Icon(Icons.compare_arrows),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (product != null &&
                product!.size.isNotEmpty &&
                !name.toLowerCase().contains(product!.size.toLowerCase()))
              Text(product!.size, style: Theme.of(context).textTheme.bodySmall),
            Text(
              line.purchaseLabel,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                CurrencyText.cents(
                  cents: line.netAmountCents,
                  prefix: 'Amount ',
                ),
                CurrencyText.cents(
                  cents: line.costPerPieceCents,
                  suffix: ' / piece',
                ),
              ],
            ),
            if (line.discountCents > 0)
              CurrencyText.cents(
                cents: line.discountCents,
                prefix: 'Line discount ',
              ),
            if (line.originalDescription != name) ...[
              const SizedBox(height: 4),
              Text(
                'Receipt: ${line.originalDescription}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            Text(
              'Source: Photo ${line.sourcePage + 1}',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
