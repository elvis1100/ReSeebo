import 'package:flutter/material.dart';
import '../../../core/models/product.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/currency_text.dart';
import '../../../core/widgets/shared_widgets.dart' show LocalPhoto;
import '../../../core/utils/date_formatter.dart';

/// Interactive card rendering a product in the store owner's catalog.
///
/// Displays product branding, variant, unit size, reference unit cost,
/// and quick navigation to multi-supplier price comparisons.
class ProductCatalogItem extends StatelessWidget {
  final Product product;
  final double? latestUnitCost;
  final double? suggestedPrice;
  final DateTime? latestPurchaseDate;
  final VoidCallback? onTap;

  const ProductCatalogItem({
    super.key,
    required this.product,
    this.latestUnitCost,
    this.suggestedPrice,
    this.latestPurchaseDate,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: AppSpacing.compactCardPadding,
      child: Row(
        children: [
          LocalPhoto(path: product.photoPath, size: 48, fit: BoxFit.contain),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.displayName,
                  style: AppTypography.headingSmall.copyWith(fontSize: 15),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: AppSpacing.s,
                  runSpacing: 4,
                  children: [
                    if (product.category.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          product.category,
                          style: AppTypography.caption.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                    Text(product.sizeUnit, style: AppTypography.caption),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (latestUnitCost != null) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Cost / pc: ',
                      style: AppTypography.caption.copyWith(fontSize: 11),
                    ),
                    CurrencyText(
                      latestUnitCost!,
                      style: AppTypography.tableCellNumber.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
              if (latestPurchaseDate != null)
                Text(
                  DateFormatter.format(latestPurchaseDate!),
                  style: AppTypography.caption,
                ),
              if (latestUnitCost == null)
                const Text('No price yet', style: AppTypography.bodySmall),
              if (suggestedPrice != null) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Suggested: ',
                      style: AppTypography.caption.copyWith(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    CurrencyText(
                      suggestedPrice!,
                      style: AppTypography.tableCellNumber.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(width: AppSpacing.xs),
          const Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}
