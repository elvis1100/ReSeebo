import 'package:flutter/material.dart';
import '../../../core/models/comparison.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_card.dart';

/// Responsive table showing identical product costs across multiple suppliers.
///
/// Designed to fit comfortably on 360dp–412dp Android screens without horizontal clipping.
class SupplierComparisonTable extends StatelessWidget {
  final List<SupplierPriceRow> rows;
  final ValueChanged<String>? onReceiptTap;

  const SupplierComparisonTable({
    super.key,
    required this.rows,
    this.onReceiptTap,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              const Icon(
                Icons.compare_arrows_rounded,
                size: 40,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: AppSpacing.s),
              const Text(
                'No supplier comparison data yet.',
                style: AppTypography.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s),
          child: AppCard(
            onTap: () => onReceiptTap?.call(row.sourceReceiptId),
            padding: const EdgeInsets.all(AppSpacing.m),
            backgroundColor: row.isLowestPrice
                ? AppColors.priceCheaperBg.withValues(alpha: 0.25)
                : AppColors.surfaceCard,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Supplier name & lowest price pill
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        row.purchase.supplier.label,
                        style: AppTypography.headingSmall.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: row.isLowestPrice
                              ? AppColors.primary
                              : AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s),
                    if (row.isLowestPrice)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.priceCheaper,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusPill,
                          ),
                        ),
                        child: Text(
                          'LOWEST',
                          style: AppTypography.caption.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                            letterSpacing: 0.5,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusPill,
                          ),
                        ),
                        child: Text(
                          '+${CurrencyFormatter.format(row.differenceVsBest)} / pc',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),

                // Package and purchase date details
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        row.packageDescription,
                        style: AppTypography.bodySmall.copyWith(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      DateFormatter.format(row.latestPurchaseDate),
                      style: AppTypography.caption,
                    ),
                  ],
                ),
                const Divider(height: 16),

                // Cost per piece & tap receipt hint
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text('Unit Cost: ', style: AppTypography.caption),
                        Text(
                          CurrencyFormatter.format(row.costPerPiece),
                          style: AppTypography.tableCellNumber.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: row.isLowestPrice
                                ? AppColors.priceCheaper
                                : AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          ' / pc',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Receipt',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
