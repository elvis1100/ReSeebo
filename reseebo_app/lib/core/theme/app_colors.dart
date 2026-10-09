import 'package:flutter/material.dart';

/// Centralized color palette for Reseebo based on the
/// "Palengke Green & Clean Ledger" design system.
abstract final class AppColors {
  // Brand Primary (Emerald/Forest)
  static const Color primary = Color(0xFF0F5132);
  static const Color primaryLight = Color(0xFF198754);
  static const Color primaryDark = Color(0xFF0A3622);
  static const Color primarySurface = Color(0xFFE8F5E9);

  // Accent & Action (Warm Amber)
  static const Color accent = Color(0xFFD97706);
  static const Color accentLight = Color(0xFFFEF3C7);
  static const Color accentDark = Color(0xFFB45309);

  // Backgrounds & Surfaces
  static const Color background = Color(0xFFF8FAFC);
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color surfaceSubtle = Color(0xFFF1F5F9);
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderFocused = Color(0xFF0F5132);

  // Text Tokens
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textInverse = Color(0xFFFFFFFF);

  // Price Trend & Status Signals
  static const Color priceCheaper = Color(0xFF16A34A);
  static const Color priceCheaperBg = Color(0xFFDCFCE7);
  static const Color priceIncrease = Color(0xFFDC2626);
  static const Color priceIncreaseBg = Color(0xFFFEE2E2);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningBg = Color(0xFFFEF3C7);
  static const Color info = Color(0xFF0284C7);
  static const Color infoBg = Color(0xFFE0F2FE);
}
