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
              Text(
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
            padding: AppSpacing.compactCardPadding,
            backgroundColor: row.isLowestPrice
                ? AppColors.priceCheaperBg.withValues(alpha: 0.25)
                : AppColors.surfaceCard,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Supplier name & Best Price pill
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        row.supplierName,
                        style: AppTypography.headingSmall.copyWith(
                          fontSize: 14,
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
                          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 13,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'BEST PRICE',
                              style: AppTypography.caption.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 10,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warningBg,
                          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                        ),
                        child: Text(
                          '+${CurrencyFormatter.format(row.differenceVsBest)} / pc',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.accentDark,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),

                // Package and purchase date details
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      row.packageDescription,
                      style: AppTypography.bodySmall.copyWith(fontSize: 12),
                    ),
                    Text(
                      'Bought: ${DateFormatter.format(row.latestPurchaseDate)}',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
                const Divider(height: 12),

                // Cost per piece & source receipt link
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
                    InkWell(
                      onTap: () => onReceiptTap?.call(row.sourceReceiptId),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.receipt_rounded,
                              size: 14,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'View Receipt',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
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
