import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/currency_formatter.dart';

enum TrendDirection { cheaper, higher, neutral, ambiguous }

/// Reusable badge indicating price differences or changes.
/// Implements dual-encoding (icon + color + label) for accessible visibility.
class TrendBadge extends StatelessWidget {
  final num? differenceInPesos;
  final double? percentage;
  final bool isBestPrice;
  final String? customLabel;

  const TrendBadge({
    super.key,
    this.differenceInPesos,
    this.percentage,
    this.isBestPrice = false,
    this.customLabel,
  });

  const TrendBadge.lowest({super.key})
      : differenceInPesos = null,
        percentage = null,
        isBestPrice = true,
        customLabel = 'Lowest';

  TrendDirection get direction {
    if (isBestPrice) return TrendDirection.cheaper;
    if (differenceInPesos == null && customLabel != null) {
      return TrendDirection.ambiguous;
    }
    final diff = differenceInPesos ?? 0;
    if (diff < 0) return TrendDirection.cheaper;
    if (diff > 0) return TrendDirection.higher;
    return TrendDirection.neutral;
  }

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;
    String label;

    if (isBestPrice) {
      bg = AppColors.priceCheaperBg;
      fg = AppColors.priceCheaper;
      icon = Icons.check_circle_rounded;
      label = customLabel ?? 'Lowest';
    } else {
      switch (direction) {
        case TrendDirection.cheaper:
          bg = AppColors.priceCheaperBg;
          fg = AppColors.priceCheaper;
          icon = Icons.arrow_downward_rounded;
          label = customLabel ??
              (percentage != null
                  ? '${CurrencyFormatter.formatDifference(differenceInPesos)} (${CurrencyFormatter.formatPercentage(percentage?.abs())})'
                  : CurrencyFormatter.formatDifference(differenceInPesos));
          break;
        case TrendDirection.higher:
          bg = AppColors.priceIncreaseBg;
          fg = AppColors.priceIncrease;
          icon = Icons.arrow_upward_rounded;
          label = customLabel ??
              (percentage != null
                  ? '${CurrencyFormatter.formatDifference(differenceInPesos)} (+${CurrencyFormatter.formatPercentage(percentage?.abs())})'
                  : CurrencyFormatter.formatDifference(differenceInPesos));
          break;
        case TrendDirection.neutral:
          bg = AppColors.surfaceSubtle;
          fg = AppColors.textSecondary;
          icon = Icons.remove_rounded;
          label = customLabel ?? 'Same';
          break;
        case TrendDirection.ambiguous:
          bg = AppColors.warningBg;
          fg = AppColors.warning;
          icon = Icons.help_outline_rounded;
          label = customLabel ?? 'Check';
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.xxs + 1,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: fg.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              fontFeatures: [const FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
