import 'package:flutter/material.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';

class SupplierComparison extends StatelessWidget {
  const SupplierComparison({
    super.key,
    required this.rows,
    required this.selectedSupplierId,
    required this.onSelect,
    required this.onReceipt,
  });
  final List<SupplierPriceRow> rows;
  final String? selectedSupplierId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onReceipt;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Latest recorded supplier prices',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      const Text(
        'Select a supplier cost for your pricing calculator. These are dated purchases, not current offers.',
        style: TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 12),
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        row.purchase.supplier.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Semantics(
                      selected: selectedSupplierId == row.purchase.supplier.id,
                      inMutuallyExclusiveGroup: true,
                      child: IconButton(
                        tooltip: selectedSupplierId == row.purchase.supplier.id
                            ? 'Selected cost: ${row.purchase.supplier.label}'
                            : 'Use cost: ${row.purchase.supplier.label}',
                        onPressed: () => onSelect(row.purchase.supplier.id),
                        icon: Icon(
                          selectedSupplierId == row.purchase.supplier.id
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  purchaseDate(
                    row.purchase.purchasedAt,
                    withTime: row.purchase.hasPurchaseTime,
                  ),
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                _DataRow(
                  label: 'Cost per piece',
                  value: pesos(row.purchase.costPerPieceCents),
                  bold: true,
                ),
                _DataRow(
                  label: 'Recorded quantity',
                  value: row.purchase.purchaseLabel,
                ),
                _DataRow(
                  label: 'Difference vs best',
                  value: row.differenceCents.abs() < .00001
                      ? 'Lowest recorded'
                      : '+${pesos(row.differenceCents)} / pc',
                  bold: row.differenceCents.abs() < .00001,
                ),
                TextButton.icon(
                  onPressed: () => onReceipt(row.purchase.receiptId),
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('View source receipt'),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class PriceHistoryList extends StatelessWidget {
  const PriceHistoryList({
    super.key,
    required this.records,
    required this.onReceipt,
  });
  final List<PriceHistoryRecord> records;
  final ValueChanged<String> onReceipt;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final row in records)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.purchase.supplier.label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  purchaseDate(
                    row.purchase.purchasedAt,
                    withTime: row.purchase.hasPurchaseTime,
                  ),
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                _DataRow(
                  label: 'Purchase cost / pc',
                  value: pesos(row.purchase.costPerPieceCents),
                  bold: true,
                ),
                if (row.previousCostPerPieceCents != null)
                  _DataRow(
                    label: 'Previous at supplier',
                    value: '${pesos(row.previousCostPerPieceCents!)} / pc',
                  ),
                const SizedBox(height: 4),
                _ChangeBadge(record: row),
                if (row.orderingNote != null) ...[
                  const SizedBox(height: 8),
                  Notice(message: row.orderingNote!, warning: true),
                ],
                const SizedBox(height: 8),
                Text(
                  'Recorded ${purchaseDate(row.purchase.recordedAt, withTime: true)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                TextButton.icon(
                  onPressed: () => onReceipt(row.purchase.receiptId),
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('View source receipt'),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge({required this.record});
  final PriceHistoryRecord record;
  @override
  Widget build(BuildContext context) {
    final change = record.changeCents;
    if (change == null) {
      return const Text(
        'First recorded purchase at this supplier',
        style: TextStyle(color: AppColors.muted),
      );
    }
    final unchanged = change.abs() < .00001;
    final increase = change > 0;
    final color = unchanged
        ? AppColors.muted
        : increase
        ? AppColors.danger
        : AppColors.primary;
    final label = unchanged
        ? 'No change'
        : increase
        ? 'Price increased'
        : 'Price decreased';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          unchanged
              ? Icons.remove
              : increase
              ? Icons.arrow_upward
              : Icons.arrow_downward,
          color: color,
          size: 18,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$label · ${increase
                ? '+'
                : unchanged
                ? ''
                : '−'}${pesos(change.abs())} (${increase
                ? '+'
                : unchanged
                ? ''
                : '−'}${percent(record.changePercent?.abs() ?? 0)})',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({required this.label, required this.value, this.bold = false});
  final String label;
  final String value;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (MediaQuery.textScalerOf(context).scale(1) > 1.15) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: AppColors.muted)),
              Text(
                value,
                style: AppTheme.moneyStyle.copyWith(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: AppColors.muted),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: AppTheme.moneyStyle.copyWith(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
