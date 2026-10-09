import 'package:flutter/material.dart';

import '../../../core/models/store_profile.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';

/// Compact store identity; receipt and product counts belong to the tabs.
class StatHeader extends StatelessWidget {
  final StoreProfile profile;
  final VoidCallback? onSettingsTap;

  const StatHeader({super.key, required this.profile, this.onSettingsTap});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Store settings',
    child: Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(AppSpacing.radiusM),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primaryDark,
              AppColors.primary,
              AppColors.primaryLight,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: InkWell(
          onTap: onSettingsTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.storeName,
                        style: AppTypography.headingMedium.copyWith(
                          fontSize: 17,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (profile.ownerName.trim().isNotEmpty)
                        Text(
                          profile.ownerName,
                          style: AppTypography.bodySmall.copyWith(
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Text(
                    profile.defaultMarkupPercent == null
                        ? 'Set markup'
                        : '${CurrencyFormatter.formatPercentage(profile.defaultMarkupPercent!)} markup',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
