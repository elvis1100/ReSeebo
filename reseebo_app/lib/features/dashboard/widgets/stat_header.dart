import 'package:flutter/material.dart';
import '../../../core/models/store_profile.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_card.dart';

/// Clean, understated store overview card with essential store metadata.
///
/// Avoids loud marketing banners, presenting store credentials like a sleek
/// modern point-of-sale ledger.
class StatHeader extends StatelessWidget {
  final StoreProfile profile;
  final int totalReceipts;
  final int totalProducts;
  final VoidCallback? onSettingsTap;

  const StatHeader({
    super.key,
    required this.profile,
    this.totalReceipts = 0,
    this.totalProducts = 0,
    this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onSettingsTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.m,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.storeName,
                      style: AppTypography.headingMedium.copyWith(
                        fontSize: 17,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (profile.ownerName != null &&
                        profile.ownerName!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        profile.ownerName!,
                        style: AppTypography.bodySmall.copyWith(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  '${CurrencyFormatter.formatPercentage(profile.defaultMarkupPercentage)} Markup',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            children: [
              _buildMiniMetric(
                label: 'Receipts',
                value: '$totalReceipts',
              ),
              Container(
                width: 1,
                height: 24,
                color: AppColors.border,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
              ),
              _buildMiniMetric(
                label: 'Tracked Items',
                value: '$totalProducts',
              ),
              Container(
                width: 1,
                height: 24,
                color: AppColors.border,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
              ),
              _buildMiniMetric(
                label: 'Storage',
                value: 'On-Device',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetric({
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(
            fontSize: 11,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: AppTypography.headingSmall.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
