import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

export 'app_colors.dart';
export 'app_spacing.dart';
export 'app_typography.dart';

/// Configures the unified Material 3 theme for Reseebo.
abstract final class AppTheme {
  static ThemeData get light => lightTheme;

  static const moneyStyle = TextStyle(
    fontFamily: 'Inter',
    fontFeatures: [FontFeature.tabularFigures()],
    fontWeight: FontWeight.w700,
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.textInverse,
        primaryContainer: AppColors.primarySurface,
        onPrimaryContainer: AppColors.primaryDark,
        secondary: AppColors.primary,
        onSecondary: AppColors.textInverse,
        secondaryContainer: AppColors.primarySurface,
        onSecondaryContainer: AppColors.primaryDark,
        tertiary: AppColors.primary,
        onTertiary: AppColors.textInverse,
        tertiaryContainer: AppColors.primarySurface,
        onTertiaryContainer: AppColors.primaryDark,
        surface: AppColors.surfaceCard,
        onSurface: AppColors.textPrimary,
        error: AppColors.priceIncrease,
        onError: AppColors.textInverse,
      ),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surfaceCard,
        foregroundColor: AppColors.textPrimary,
        elevation: 0.0,
        scrolledUnderElevation: 1.0,
        centerTitle: false,
        titleTextStyle: AppTypography.headingMedium.copyWith(
          fontFamily: 'Inter',
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceCard,
        elevation: 0.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          side: const BorderSide(color: AppColors.border, width: 1.0),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textInverse,
          elevation: 0.0,
          padding: AppSpacing.buttonPadding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusS),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15.0,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: AppSpacing.buttonPadding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusS),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15.0,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceCard,
        contentPadding: AppSpacing.inputPadding,
        hintStyle: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
        labelStyle: AppTypography.bodySmall,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusS),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusS),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusS),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusS),
          borderSide: const BorderSide(
            color: AppColors.priceIncrease,
            width: 1.5,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1.0,
        space: 1.0,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceCard,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textMuted,
        elevation: 0.0,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
