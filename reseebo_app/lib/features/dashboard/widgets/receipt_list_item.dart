import 'package:flutter/material.dart';
import '../../../core/models/receipt.dart';
import '../../../core/models/supplier.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/currency_text.dart';

class ReceiptListItem extends StatelessWidget {
  final Receipt receipt;
  final Supplier? supplier;
  final VoidCallback? onTap;

  const ReceiptListItem({
    super.key,
    required this.receipt,
    this.supplier,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final supplierName = supplier?.displayName ?? 'Saved Supplier';

    return AppCard(
      onTap: onTap,
      padding: AppSpacing.compactCardPadding,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(AppSpacing.radiusS),
            ),
            child: const Icon(
              Icons.receipt_outlined,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  supplierName,
                  style: AppTypography.headingSmall.copyWith(fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      DateFormatter.format(receipt.purchaseDate),
                      style: AppTypography.caption,
                    ),
                    const SizedBox(width: AppSpacing.s),
                    Text(
                      '•  ${receipt.itemCount} ${receipt.itemCount == 1 ? 'item' : 'items'}',
                      style: AppTypography.caption,
                    ),
                    if (receipt.receiptNumber != null) ...[
                      const SizedBox(width: AppSpacing.s),
                      Text(
                        '#${receipt.receiptNumber}',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CurrencyText(
                receipt.totalAmount,
                style: AppTypography.tableCellNumber.copyWith(
                  fontSize: 16,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 2),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
