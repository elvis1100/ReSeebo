import 'package:flutter/material.dart';
import '../../../core/models/restock_estimate.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_card.dart';

/// Card rendering a supplier restock option with whole-pack ceil rounding,
/// travel fare inclusion, and net savings evaluation.
class RestockPlannerCard extends StatelessWidget {
  final RestockSupplierOption option;
  final bool isRecommended;
  final int targetPieces;

  const RestockPlannerCard({
    super.key,
    required this.option,
    this.isRecommended = false,
    required this.targetPieces,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: AppSpacing.compactCardPadding,
      backgroundColor: isRecommended
          ? AppColors.primarySurface.withValues(alpha: 0.5)
          : AppColors.surfaceCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Supplier Name & Recommended badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  option.supplierName,
                  style: AppTypography.headingSmall.copyWith(
                    fontSize: 15,
                    color: isRecommended
                        ? AppColors.primary
                        : AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isRecommended)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.thumb_up_alt_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'BEST OPTION',
                        style: AppTypography.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),

          // Ceil pack calculation pill
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s + 2,
              vertical: AppSpacing.xs + 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(AppSpacing.radiusS),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.all_inbox_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    'Need $targetPieces pcs → Buy ${option.packsNeeded} packs (${option.totalPiecesPurchased} pcs @ ${CurrencyFormatter.format(option.packCost)}/pack)',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s),

          // Breakdown: Purchase cost + Travel fare
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Product Cost (${option.packsNeeded} pk):',
                style: AppTypography.bodySmall,
              ),
              Text(
                CurrencyFormatter.format(option.totalPurchaseCost),
                style: AppTypography.tableCellNumber,
              ),
            ],
          ),
          if (option.travelCost > 0) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Travel Fare (Trike/Jeep):',
                  style: AppTypography.bodySmall,
                ),
                Text(
                  '+${CurrencyFormatter.format(option.travelCost)}',
                  style: AppTypography.tableCellNumber.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
          const Divider(height: 12),

          // Total Out-of-Pocket Cost & Net Savings
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Capital Needed',
                    style: AppTypography.caption.copyWith(fontSize: 11),
                  ),
                  Text(
                    CurrencyFormatter.format(option.totalCostWithTravel),
                    style: AppTypography.priceHighlight.copyWith(
                      fontSize: 18,
                      color: isRecommended
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              if (option.netSavingsAfterTravel > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.priceCheaperBg,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusS),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Net Savings',
                        style: AppTypography.caption.copyWith(
                          fontSize: 10,
                          color: AppColors.priceCheaper,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Save ${CurrencyFormatter.format(option.netSavingsAfterTravel)}',
                        style: AppTypography.tableCellNumber.copyWith(
                          color: AppColors.priceCheaper,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
