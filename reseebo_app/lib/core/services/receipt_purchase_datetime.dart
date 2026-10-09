import '../models/models.dart';

/// Receipt date/time evidence stays an editable suggestion. Numeric month/day
/// order is accepted only when unambiguous; a clock needs a date or time label
/// or an adjacent date row. Unrelated product/card dates are excluded.
class ReceiptPurchaseDateTime {
  static final _unrelated = RegExp(
    r'\b(?:exp(?:iry|iration|ire[sd]?)?|mfg|manufacture|manufactured|manufacturing|production|packed|card|birthday|dob|opening|closing|delivery|printed|reprint|accred(?:itation)?|permit|ptu|issued?)\b|\b(?:best\s*before|use\s*by|valid\s*(?:thru|until|through))\b',
    caseSensitive: false,
  );
  static const _month =
      r'(JAN(?:UARY)?|FEB(?:RUARY)?|MAR(?:CH)?|APR(?:IL)?|MAY|JUN(?:E)?|JUL(?:Y)?|AUG(?:UST)?|SEP(?:T(?:EMBER)?)?|OCT(?:OBER)?|NOV(?:EMBER)?|DEC(?:EMBER)?)';
  static final _iso = RegExp(r'\b(20\d{2})[./-](\d{1,2})[./-](\d{1,2})\b');
  static final _dayFirst = RegExp(
    r'\b(\d{1,2})[\s/-]+' + _month + r'\.?[\s/,-]+(20\d{2}|\d{2})\b(?![\d:])',
    caseSensitive: false,
  );
  static final _monthFirst = RegExp(
    r'\b' +
        _month +
        r'\.?[\s/-]+(\d{1,2})(?:st|nd|rd|th)?[\s/,-]+(20\d{2}|\d{2})\b(?![\d:])',
    caseSensitive: false,
  );
  static final _numeric = RegExp(
    r'\b(\d{1,2})[./-](\d{1,2})[./-](20\d{2}|\d{2})\b',
  );
  static final _clock = RegExp(
    r'(?<![\d:+-])\b(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\s*([ap])\.?m\.?)?(?![\d:a-z])',
    caseSensitive: false,
  );
  static final _timeLabel = RegExp(r'\btime\b', caseSensitive: false);

  /// [rows] must retain printed row order. Empty rows can separate photos so
  /// an unlabeled clock cannot gain an accidental neighbor on another page.
  PurchaseDateTimeSuggestion suggest(
    List<String> rows, {
    NumericDateOrder? dateOrder,
  }) {
    var ambiguousDate = false;
    final dates = <DateTime>{};
    final dateRows = <int>{};
    final warnings = <String>{};
    for (var index = 0; index < rows.length; index++) {
      final text = rows[index];
      if (_unrelated.hasMatch(text) ||
          (index > 0 && _unrelated.hasMatch(rows[index - 1]) &&
           RegExp(r'^[\d./:\s-]+$').hasMatch(text))) continue;
      void accept(DateTime? date, {bool ambiguous = false}) {
        if (date != null) {
          dates.add(date);
          dateRows.add(index);
        } else {
          warnings.add(
            ambiguous
                ? 'The printed date is ambiguous. Confirm the purchase date.'
                : 'A printed date is invalid or unclear. Check the purchase date.',
          );
        }
      }

      for (final match in _iso.allMatches(text)) {
        accept(
          _validDate(
            _year(match[1]!),
            int.parse(match[2]!),
            int.parse(match[3]!),
          ),
        );
      }
      for (final match in _dayFirst.allMatches(text)) {
        accept(
          _validDate(
            _year(match[3]!),
            _monthNumber(match[2]!),
            int.parse(match[1]!),
          ),
        );
      }
      for (final match in _monthFirst.allMatches(text)) {
        accept(
          _validDate(
            _year(match[3]!),
            _monthNumber(match[1]!),
            int.parse(match[2]!),
          ),
        );
      }
      for (final match in _numeric.allMatches(text)) {
        final first = int.parse(match[1]!);
        final second = int.parse(match[2]!);
        final year = _year(match[3]!);
        if (first > 12) {
          accept(_validDate(year, second, first));
        } else if (second > 12 || first == second) {
          accept(_validDate(year, first, second));
        } else if (dateOrder != null) {
          accept(
            dateOrder == NumericDateOrder.dayFirst
                ? _validDate(year, second, first)
                : _validDate(year, first, second),
          );
        } else {
          ambiguousDate = first > 0 && second > 0;
          accept(null, ambiguous: ambiguousDate);
        }
      }
    }
    if (ambiguousDate && dateOrder == null) {
      final candidates = <PurchaseDateCandidate>[];
      for (final order in NumericDateOrder.values) {
        final suggestion = suggest(rows, dateOrder: order);
        if (suggestion.purchasedAt != null) {
          candidates.add(
            PurchaseDateCandidate(
              suggestion.purchasedAt!,
              order,
              suggestion.hasPurchaseTime,
            ),
          );
        }
      }
      return PurchaseDateTimeSuggestion(
        candidates: candidates,
        warnings: warnings.toList(),
      );
    }
    if (dates.length > 1) {
      warnings.add(
        'Purchase dates differ on the receipt. Check and choose the correct date.',
      );
      return PurchaseDateTimeSuggestion(warnings: warnings.toList());
    }
    if (dates.isEmpty) {
      return PurchaseDateTimeSuggestion(warnings: warnings.toList());
    }
    final date = dates.single;
    final times = <(int, int, int)>{};
    for (var index = 0; index < rows.length; index++) {
      final text = rows[index];
      if (_unrelated.hasMatch(text) ||
          (index > 0 && _unrelated.hasMatch(rows[index - 1]) &&
           RegExp(r'^[\d./:\s-]+$').hasMatch(text))) continue;
      final matches = _clock.allMatches(text).toList();
      final labeled = _timeLabel.hasMatch(text);
      final adjacent =
          dateRows.contains(index - 1) || dateRows.contains(index + 1);
      // Nearby item descriptions and business hours are not transaction clocks.
      final standalone =
          matches.length == 1 &&
          text
              .replaceRange(matches.single.start, matches.single.end, '')
              .trim()
              .isEmpty;
      if (!dateRows.contains(index) && !labeled && !(adjacent && standalone)) {
        continue;
      }
      for (final match in matches) {
        final time = _validTime(match);
        if (time == null) {
          warnings.add(
            'A printed time is invalid or unclear. Check the purchase time.',
          );
        } else {
          times.add(time);
        }
      }
    }
    if (times.length > 1) {
      warnings.add(
        'Purchase times differ on the receipt. Check the time or leave it unknown.',
      );
      return PurchaseDateTimeSuggestion(
        purchasedAt: date,
        warnings: warnings.toList(),
      );
    }
    final time = times.singleOrNull;
    return PurchaseDateTimeSuggestion(
      purchasedAt: time == null
          ? date
          : DateTime(
              date.year,
              date.month,
              date.day,
              time.$1,
              time.$2,
              time.$3,
            ),
      hasPurchaseTime: time != null,
      warnings: warnings.toList(),
    );
  }

  bool isMetadata(String text) =>
      _iso.hasMatch(text) ||
      _dayFirst.hasMatch(text) ||
      _monthFirst.hasMatch(text) ||
      _numeric.hasMatch(text) ||
      _clock.hasMatch(text);

  int _year(String text) {
    final year = int.parse(text);
    // Receipts are modern purchases; short years suggest 2000–2099 and always
    // remain unconfirmed until the owner checks the original image.
    return year < 100 ? 2000 + year : year;
  }

  int _monthNumber(String text) =>
      const [
        'JAN',
        'FEB',
        'MAR',
        'APR',
        'MAY',
        'JUN',
        'JUL',
        'AUG',
        'SEP',
        'OCT',
        'NOV',
        'DEC',
      ].indexOf(text.substring(0, 3).toUpperCase()) +
      1;

  DateTime? _validDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  (int, int, int)? _validTime(RegExpMatch match) {
    var hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    final second = int.parse(match[3] ?? '0');
    final meridiem = match[4]?.toLowerCase();
    if (meridiem != null) {
      if (hour < 1 || hour > 12) return null;
      hour = hour % 12 + (meridiem == 'p' ? 12 : 0);
    }
    if (hour > 23 || minute > 59 || second > 59) return null;
    return (hour, minute, second);
  }
}

class PurchaseDateTimeSuggestion {
  const PurchaseDateTimeSuggestion({
    this.purchasedAt,
    this.hasPurchaseTime = false,
    this.warnings = const [],
    this.candidates = const [],
  });

  final DateTime? purchasedAt;
  final bool hasPurchaseTime;
  final List<String> warnings;
  final List<PurchaseDateCandidate> candidates;
}
