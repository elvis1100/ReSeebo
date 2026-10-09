import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/currency_formatter.dart';

/// Renders a currency value with strict tabular figures and consistent peso symbol styling.
class CurrencyText extends StatelessWidget {
  final num? amount;
  final TextStyle? style;
  final Color? color;
  final bool showDifferenceSign;
  final String? suffix;

  const CurrencyText(
    this.amount, {
    super.key,
    this.style,
    this.color,
    this.showDifferenceSign = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? Theme.of(context).textTheme.bodyMedium;
    final effectiveStyle = (baseStyle ?? const TextStyle()).copyWith(
      color: color ?? baseStyle?.color ?? AppColors.textPrimary,
      fontFeatures: [const FontFeature.tabularFigures()],
      fontWeight: baseStyle?.fontWeight ?? FontWeight.w600,
    );

    final formatted = showDifferenceSign
        ? CurrencyFormatter.formatDifference(amount)
        : CurrencyFormatter.format(amount);

    if (suffix == null) {
      return Text(formatted, style: effectiveStyle);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(formatted, style: effectiveStyle),
        const SizedBox(width: 2),
        Text(
          suffix!,
          style: effectiveStyle.copyWith(
            fontSize: (effectiveStyle.fontSize ?? 14) * 0.8,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
