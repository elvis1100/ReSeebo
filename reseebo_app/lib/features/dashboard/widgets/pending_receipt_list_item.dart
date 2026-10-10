import 'package:flutter/material.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_card.dart';
import '../../receipts/widgets/receipt_review_status.dart';

class PendingReceiptListItem extends StatelessWidget {
  const PendingReceiptListItem({super.key, required this.entry, this.onTap});
  final LedgerEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    padding: AppSpacing.compactCardPadding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          entry.supplierDisplay,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        const ReceiptReviewStatus(),
        const SizedBox(height: 6),
        Text('Saved ${purchaseDate(entry.recordedAt.toLocal())}'),
        Text(
          entry.provisionalTotalCents == null
              ? 'Total not available'
              : 'Provisional total: ${pesos(entry.provisionalTotalCents!)}',
        ),
        if (entry.confirmedReceiptId != null)
          const Text('Correction pending; the saved purchase remains active.'),
      ],
    ),
  );
}
