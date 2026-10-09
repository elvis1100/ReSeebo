import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/currency_formatter.dart';

/// Renders a currency value with strict tabular figures and consistent peso symbol styling.
class CurrencyText extends StatelessWidget {
  final num? amount;
  final TextStyle? style;
  final Color? color;
  final bool showDifferenceSign;
  final String prefix;
  final String? suffix;

  const CurrencyText(
    this.amount, {
    super.key,
    this.style,
    this.color,
    this.showDifferenceSign = false,
    this.prefix = '',
    this.suffix,
  });

  const CurrencyText.cents({
    super.key,
    required num cents,
    this.style,
    this.color,
    this.showDifferenceSign = false,
    this.prefix = '',
    this.suffix,
  }) : amount = cents / 100.0;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? Theme.of(context).textTheme.bodyMedium;
    final effectiveStyle = (baseStyle ?? const TextStyle()).copyWith(
      color: color ?? baseStyle?.color ?? AppColors.textPrimary,
      fontFeatures: [const FontFeature.tabularFigures()],
      fontWeight: baseStyle?.fontWeight ?? FontWeight.w600,
    );

    final rawFormatted = showDifferenceSign
        ? CurrencyFormatter.formatDifference(amount)
        : CurrencyFormatter.format(amount);
    final formatted = '$prefix$rawFormatted';

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
