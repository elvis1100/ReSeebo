import 'package:flutter/material.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../state/comparison_controller.dart';
import 'supplier_comparison.dart';

class ProductSummaryCard extends StatelessWidget {
  const ProductSummaryCard({
    super.key,
    required this.product,
    required this.onEdit,
  });
  final Product product;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) => AppCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(AppRadii.control),
          child: Semantics(
            button: true,
            label: 'Edit product photo',
            child: LocalPhoto(path: product.photoPath, size: 64),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                product.identity,
                style: const TextStyle(color: AppColors.muted),
              ),
              if (product.category.isNotEmpty)
                Text('Category: ${product.category}'),
              if (product.barcode.isNotEmpty)
                Text('Barcode: ${product.barcode}'),
            ],
          ),
        ),
      ],
    ),
  );
}

class HistoricalLowCard extends StatelessWidget {
  const HistoricalLowCard({
    super.key,
    required this.purchase,
    required this.onReceipt,
  });
  final PurchaseRecord purchase;
  final ValueChanged<String> onReceipt;
  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lowest historical purchase',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        CurrencyText(
          cents: purchase.costPerPieceCents,
          suffix: ' / pc · ${purchase.supplier.label}',
        ),
        Text(
          purchaseDate(
            purchase.purchasedAt,
            withTime: purchase.hasPurchaseTime,
          ),
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Historical low may differ from a supplier’s latest recorded price.',
          style: TextStyle(color: AppColors.muted),
        ),
        TextButton.icon(
          onPressed: () => onReceipt(purchase.receiptId),
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('View source receipt'),
        ),
      ],
    ),
  );
}

class ComparisonHistorySection extends StatelessWidget {
  const ComparisonHistorySection({
    super.key,
    required this.controller,
    required this.onReceipt,
  });
  final ComparisonController controller;
  final ValueChanged<String> onReceipt;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Price history', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: AppSpacing.sm),
      const Text(
        'Grouped by supplier, oldest to newest. Each change compares this exact product with its previous purchase at that supplier. Same-day records stay separate.',
        style: TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: AppSpacing.lg),
      DropdownButtonFormField<String>(
        key: ValueKey(controller.historySupplierId),
        initialValue: controller.historySupplierId ?? '',
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Filter history by supplier',
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('All suppliers')),
          for (final row in controller.data!.latestPrices)
            DropdownMenuItem(
              value: row.purchase.supplier.id,
              child: Text(
                row.purchase.supplier.label,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (id) => controller.filterHistory(id == '' ? null : id),
      ),
      const SizedBox(height: AppSpacing.md),
      PriceHistoryList(
        records: controller.filteredHistory,
        onReceipt: onReceipt,
      ),
    ],
  );
}
