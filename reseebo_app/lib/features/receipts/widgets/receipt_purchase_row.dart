import 'package:flutter/material.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';

class ReceiptPurchaseRow extends StatelessWidget {
  const ReceiptPurchaseRow({
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
              Tooltip(
                message: 'Compare prices for $name',
                child: TextButton.icon(
                  onPressed: onCompare,
                  icon: const Icon(Icons.compare_arrows, size: 18),
                  label: const Text('Compare'),
                ),
              ),
            ],
          ),
          if (product != null && product!.displayTitle != name)
            Text(
              product!.displayTitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          Text(
            line.purchaseLabel,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              CurrencyText.cents(cents: line.netAmountCents, prefix: 'Amount '),
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
    );
  }
}
