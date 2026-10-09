import 'package:intl/intl.dart';

/// Formatter utilities for Philippine Peso (₱) amounts and margins.
abstract final class CurrencyFormatter {
  static final NumberFormat _pesoFormat = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  static final NumberFormat _percentFormat = NumberFormat.percentPattern('en_US');

  /// Formats amount into standard ₱ representation (e.g. `₱8.40`).
  static String format(num? amount) {
    if (amount == null) return '₱0.00';
    return _pesoFormat.format(amount);
  }

  /// Formats signed difference in pesos with directional prefix (e.g. `+₱0.40`, `-₱0.60`, `₱0.00`).
  static String formatDifference(num? diff) {
    if (diff == null || diff == 0) return '₱0.00';
    if (diff > 0) {
      return '+${_pesoFormat.format(diff)}';
    } else {
      return '-${_pesoFormat.format(diff.abs())}';
    }
  }

  /// Formats percentage value (e.g. `20%` or `+5.0%`).
  static String formatPercentage(double? percentage, {bool showSign = false}) {
    if (percentage == null) return '0%';
    final pctValue = percentage / 100.0;
    final formatted = _percentFormat.format(pctValue);
    if (showSign && percentage > 0) {
      return '+$formatted';
    }
    return formatted;
  }
}
