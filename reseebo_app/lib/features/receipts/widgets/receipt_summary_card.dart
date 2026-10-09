import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';

class ReceiptSummaryCard extends StatelessWidget {
  const ReceiptSummaryCard({super.key, required this.detail});
  final ReceiptDetail detail;
  @override
  Widget build(BuildContext context) {
    final receipt = detail.receipt;
    final pieces = detail.lines.fold<int>(
      0,
      (sum, line) => sum + line.totalPieces,
    );
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            receipt.supplier.label,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            purchaseDate(
              receipt.purchasedAt,
              withTime: receipt.hasPurchaseTime,
            ),
          ),
          if (receipt.receiptNumber.isNotEmpty)
            Text(
              'Receipt no. ${receipt.receiptNumber}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const Divider(height: 20),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recorded purchase total',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  CurrencyText.cents(
                    cents: receipt.totalCents,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: AppColors.primary),
                  ),
                ],
              ),
              Text(
                '${detail.lines.length} ${detail.lines.length == 1 ? 'item' : 'items'} · $pieces pieces',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          if (receipt.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Notes: ${receipt.notes}'),
          ],
        ],
      ),
    );
  }
}
