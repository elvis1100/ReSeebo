import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_card.dart';

/// Interactive slider and preset chips for customizing store-wide default profit markup.
class DefaultMarkupSlider extends StatelessWidget {
  final double? markupPercentage;
  final ValueChanged<double>? onChanged;

  const DefaultMarkupSlider({
    super.key,
    required this.markupPercentage,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Default markup',
                style: AppTypography.headingSmall.copyWith(fontSize: 15),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  markupPercentage == null
                      ? 'Not set'
                      : CurrencyFormatter.formatPercentage(markupPercentage!),
                  style: AppTypography.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Choose how much to add to purchase costs when suggesting selling prices. Individual products can have their own markup.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.s),

          // Continuous Slider
          if (markupPercentage != null)
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: AppColors.surfaceSubtle,
                thumbColor: AppColors.primary,
                overlayColor: AppColors.primary.withValues(alpha: 0.15),
              ),
              child: Slider(
                value: markupPercentage!.clamp(0.0, 50.0),
                min: 0.0,
                max: 50.0,
                divisions: 50,
                onChanged: onChanged,
              ),
            ),

          // Preset Chips (10%, 15%, 20%, 25%, 30%)
          Row(
            children: [10.0, 15.0, 20.0, 25.0, 30.0].map((rate) {
              final isSelected =
                  markupPercentage != null &&
                  (markupPercentage! - rate).abs() < 0.5;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.0),
                  child: InkWell(
                    onTap: onChanged == null ? null : () => onChanged!(rate),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusXs,
                        ),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        '${rate.toInt()}%',
                        style: AppTypography.caption.copyWith(
                          color: isSelected
                              ? Colors.white
                              : AppColors.textPrimary,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
