import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Reusable form input with integrated labels, helper text, and error states.
class AppTextField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final TextInputType keyboardType;
  final String? prefixText;
  final String? suffixText;
  final Widget? suffixIcon;
  final String? errorText;
  final bool readOnly;
  final List<TextInputFormatter>? inputFormatters;

  const AppTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.onChanged,
    this.keyboardType = TextInputType.text,
    this.prefixText,
    this.suffixText,
    this.suffixIcon,
    this.errorText,
    this.readOnly = false,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: errorText != null
                ? AppColors.priceIncrease
                : AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: keyboardType,
          readOnly: readOnly,
          inputFormatters: inputFormatters,
          style: AppTypography.bodyRegular.copyWith(
            fontWeight: FontWeight.w500,
            fontFeatures: keyboardType == TextInputType.number ||
                    keyboardType == const TextInputType.numberWithOptions(decimal: true)
                ? [const FontFeature.tabularFigures()]
                : null,
          ),
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefixText != null ? '$prefixText ' : null,
            prefixStyle: AppTypography.bodyRegular.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            suffixText: suffixText,
            suffixIcon: suffixIcon,
            errorText: errorText,
          ),
        ),
      ],
    );
  }
}
