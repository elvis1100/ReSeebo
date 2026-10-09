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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            product?.name ?? line.originalDescription,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (product != null) Text(product!.identity),
          const SizedBox(height: AppSpacing.sm),
          Text('Photo ${line.sourcePage + 1} · ${line.purchaseLabel}'),
          Text('Receipt: ${line.originalDescription}'),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              CurrencyText(cents: line.netAmountCents, prefix: 'Net '),
              CurrencyText(cents: line.costPerPieceCents, suffix: ' / piece'),
            ],
          ),
          if (line.discountCents > 0)
            CurrencyText(cents: line.discountCents, prefix: 'Line discount '),
          TextButton.icon(
            onPressed: onCompare,
            icon: const Icon(Icons.compare_arrows),
            label: const Text('Compare prices'),
          ),
        ],
      ),
    ),
  );
}
