import 'package:flutter/material.dart';
import '../../../core/models/store_profile.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';

/// Top header banner displaying store identity and default markup settings.
class StatHeader extends StatelessWidget {
  final StoreProfile profile;
  final VoidCallback? onSettingsTap;

  const StatHeader({
    super.key,
    required this.profile,
    this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppSpacing.radiusM),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.textInverse.withValues(alpha: 0.15),
            child: const Icon(
              Icons.storefront_rounded,
              color: AppColors.textInverse,
              size: 26,
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.storeName,
                  style: AppTypography.headingMedium.copyWith(
                    color: AppColors.textInverse,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  profile.ownerName != null
                      ? 'Owner: ${profile.ownerName}'
                      : 'Offline Tindahan Ledger',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textInverse.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          InkWell(
            onTap: onSettingsTap,
            borderRadius: BorderRadius.circular(AppSpacing.radiusS),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s + 2,
                vertical: AppSpacing.xs + 2,
              ),
              decoration: BoxDecoration(
                color: AppColors.textInverse.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.trending_up_rounded,
                    size: 14,
                    color: AppColors.accentLight,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Markup ${CurrencyFormatter.formatPercentage(profile.defaultMarkupPercentage)}',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.accentLight,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
