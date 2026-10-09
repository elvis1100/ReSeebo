import 'package:flutter/material.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';

class ReceiptLedgerItem extends StatelessWidget {
  const ReceiptLedgerItem({
    super.key,
    required this.receipt,
    required this.onTap,
  });
  final Receipt receipt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocalPhoto(
            path: receipt.imagePath,
            icon: Icons.receipt_long_outlined,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  receipt.supplier.label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  purchaseDate(
                    receipt.purchasedAt,
                    withTime: receipt.hasPurchaseTime,
                  ),
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    CurrencyText(
                      cents: receipt.totalCents,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${receipt.lineCount} ${receipt.lineCount == 1 ? 'item' : 'items'}',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.muted),
        ],
      ),
    ),
  );
}

class ProductCatalogItem extends StatelessWidget {
  const ProductCatalogItem({
    super.key,
    required this.product,
    required this.onTap,
    this.latestCostCents,
    this.latestCostDate,
  });
  final Product product;
  final double? latestCostCents;
  final DateTime? latestCostDate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocalPhoto(path: product.photoPath, icon: Icons.inventory_2_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  product.identity,
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                Text(
                  latestCostCents == null
                      ? 'No recorded purchase cost'
                      : 'Latest cost ${pesos(latestCostCents!)} / pc',
                ),
                if (latestCostDate != null)
                  Text(
                    'Bought ${purchaseDate(latestCostDate!)}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                Text(
                  product.sellingPriceCents == null
                      ? 'Selling price not set'
                      : 'Selling price ${pesos(product.sellingPriceCents!)} / pc',
                  style: const TextStyle(color: AppColors.primary),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.muted),
        ],
      ),
    ),
  );
}
