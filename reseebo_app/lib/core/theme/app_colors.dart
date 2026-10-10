import 'package:flutter/material.dart';

/// Shared palette drawn from the supplied teal, coral and cream ReSeebo logo.
abstract final class AppColors {
  static const Color primary = Color(0xFF003D43);
  static const Color primaryLight = Color(0xFF146069);
  static const Color primaryDark = Color(0xFF002D33);
  static const Color primarySurface = Color(0xFFE2F2EE);
  static const Color fieldSurface = Color(0xFFF0F8F4);

  static const Color accent = Color(0xFFFF654F);
  static const Color accentLight = Color(0xFFFFE5DD);
  static const Color accentDark = Color(0xFFAD3B2D);
  // Dark lettering keeps small text readable on the bright coral accent.
  static const Color onAccent = Color(0xFF1B282B);

  // Backgrounds & Surfaces
  static const Color background = Color(0xFFFFF7EB);
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color surfaceSubtle = Color(0xFFF4F2E9);
  static const Color border = Color(0xFFDCE5DF);
  static const Color borderFocused = primary;

  // Text Tokens
  static const Color textPrimary = Color(0xFF183C3F);
  static const Color textSecondary = Color(0xFF496466);
  static const Color textMuted = Color(0xFF5E7372);
  static const Color textInverse = Color(0xFFFFFFFF);

  // Price Trend & Status Signals
  static const Color priceCheaper = primary;
  static const Color priceCheaperBg = primarySurface;
  static const Color priceIncrease = Color(0xFF7F1D1D);
  static const Color priceIncreaseBg = Color(0xFFFEE2E2);
  static const Color warning = Color(0xFFA85712);
  static const Color warningBg = Color(0xFFFEF3C7);
  static const Color info = primaryLight;
  static const Color infoBg = primarySurface;

  // Backward compatibility tokens
  static const Color surface = Color(0xFFFFFFFF);
  static const Color text = textPrimary;
  static const Color muted = textMuted;
  static const Color danger = priceIncrease;
  static const Color amber = Color(0xFFD97706);
  static const Color softPrimary = primarySurface;
  static const Color softAmber = Color(0xFFFFF7ED);
  static const Color amberText = Color(0xFF92400E);
}
