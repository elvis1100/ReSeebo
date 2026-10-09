import 'package:flutter/material.dart';

/// Centralized spacing, padding, and layout metrics.
abstract final class AppSpacing {
  // Spacing scale
  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double s = 8.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double m = 16.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double xxxl = 48.0;

  // Corner radii
  static const double radiusXs = 4.0;
  static const double radiusS = 8.0;
  static const double radiusM = 12.0;
  static const double radiusL = 16.0;
  static const double radiusPill = 999.0;

  // Standard EdgeInsets
  static const EdgeInsets page = EdgeInsets.all(16.0);
  static const EdgeInsets screenPadding = EdgeInsets.all(16.0);
  static const EdgeInsets cardPadding = EdgeInsets.all(16.0);
  static const EdgeInsets compactCardPadding = EdgeInsets.all(12.0);
  static const EdgeInsets buttonPadding =
      EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0);
  static const EdgeInsets inputPadding =
      EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0);
}

abstract final class AppRadii {
  static const control = 12.0;
  static const card = 16.0;
  static const hero = 20.0;
}
