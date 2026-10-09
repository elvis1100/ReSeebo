import 'package:intl/intl.dart';

/// Formatter utilities for purchase and receipt dates.
abstract final class DateFormatter {
  static final DateFormat _standardDate = DateFormat('dd MMM yyyy');
  static final DateFormat _shortDate = DateFormat('dd/MM/yy');
  static final DateFormat _dateTime = DateFormat('dd MMM yyyy, hh:mm a');

  /// Formats date as `08 Oct 2026`.
  static String format(DateTime? date) {
    if (date == null) return 'No Date';
    return _standardDate.format(date);
  }

  /// Formats compact date as `08/10/26`.
  static String formatShort(DateTime? date) {
    if (date == null) return '--/--/--';
    return _shortDate.format(date);
  }

  /// Formats full timestamp as `08 Oct 2026, 02:30 PM`.
  static String formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return 'Unknown';
    return _dateTime.format(dateTime);
  }

  /// Parses string date or returns fallback.
  static DateTime? parseOrNull(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return null;
    try {
      return DateTime.parse(dateStr);
    } catch (_) {
      try {
        return _standardDate.parse(dateStr);
      } catch (_) {
        return null;
      }
    }
  }
}
