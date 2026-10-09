import '../constants/formatters.dart';
import '../models/models.dart';
import '../errors/app_exception.dart';
import 'receipt_layout.dart';

/// Layout heuristics provide editable suggestions, never confirmed purchases.
/// Unlabeled pack conversion, ambiguous dates and discounts stay owner decisions.
class ReceiptParser {
  ReceiptDraft parse({
    required String imagePath,
    required List<OcrTextLine> textLines,
    String? recognitionImagePath,
  }) {
    final rows = prepareReceiptRows(textLines);
    final draft = ReceiptDraft(
      imagePath: imagePath,
      recognitionImagePath: recognitionImagePath,
      textLines: List.of(textLines),
      rawText: recognizedReceiptText(textLines),
    );
    final amountPattern = RegExp(
      r'(?:₱|PHP\s*)?(-?\d[\d,]*\.\d{2})\s*(?:[A-Z*])?\s*$',
      caseSensitive: false,
    );
    var reachedTotal = false;
    for (var index = 0; index < rows.length; index++) {
      final text = rows[index].trim();
      if (text.isEmpty) continue;
      if (draft.supplierName.isEmpty && index < 6 && _supplierCandidate(text)) {
        draft.supplierName = text;
      }
      if (draft.purchasedAt == null) {
        final parsedDate = _date(text);
        if (parsedDate != null) {
          draft.purchasedAt = parsedDate;
          final time = _time(text);
          if (time != null) {
            draft.purchasedAt = DateTime(
              parsedDate.year,
              parsedDate.month,
              parsedDate.day,
              time.$1,
              time.$2,
              time.$3,
            );
            draft.hasPurchaseTime = true;
          }
        } else if (RegExp(
          r'\b\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4}\b',
        ).hasMatch(text)) {
          draft.warnings.add(
            'The printed date is ambiguous. Confirm the purchase date.',
          );
        }
      } else if (!draft.hasPurchaseTime &&
          RegExp(r'\btime\b', caseSensitive: false).hasMatch(text)) {
        final time = _time(text);
        if (time != null) {
          final date = draft.purchasedAt!;
          draft.purchasedAt = DateTime(
            date.year,
            date.month,
            date.day,
            time.$1,
            time.$2,
            time.$3,
          );
          draft.hasPurchaseTime = true;
        }
      }
      final number = RegExp(
        r'\b(?:receipt|invoice|transaction|o\.?r\.?)\s*(?:no\.?|number|#)\s*[:#]?\s*([\w\-]+)|\b(?:receipt|invoice|transaction|o\.?r\.?)\s*[:#]\s*([\w\-]+)',
        caseSensitive: false,
      ).firstMatch(text);
      if (number != null) {
        draft.receiptNumber = (number.group(1) ?? number.group(2))!;
      }
      if (RegExp(
        r'^(?:cash|change|tender|payment|balance)\b',
        caseSensitive: false,
      ).hasMatch(text)) {
        reachedTotal = true;
      }
      final amountMatch = amountPattern.firstMatch(text);
      if (amountMatch == null) continue;
      final cents = parsePesos(amountMatch.group(1)!.replaceFirst('-', ''));
      if (cents == null) continue;
      if (RegExp(
        r'^(?:grand\s+total|amount\s+(?:due|paid)|total(?:\s+(?:due|amount|sales))?)[\s:₱]',
        caseSensitive: false,
      ).hasMatch(text)) {
        draft.detectedTotalCents = cents;
        reachedTotal = true;
        continue;
      }
      if (RegExp(
            r'\b(?:discount|disc|saving|less)\b',
            caseSensitive: false,
          ).hasMatch(text) ||
          amountMatch.group(1)!.startsWith('-')) {
        final warning =
            'Possible discount ${amountMatch.group(1)}. Check whether the printed line amount already includes it before deducting.';
        if (draft.lines.isNotEmpty && !reachedTotal) {
          draft.lines.last.warnings.add(warning);
        } else {
          draft.warnings.add(warning);
        }
        continue;
      }
      if (reachedTotal || _metadata(text)) continue;
      var description = text.substring(0, amountMatch.start).trim();
      if (!RegExp(r'[a-z]', caseSensitive: false).hasMatch(description)) {
        continue;
      }
      int? quantity;
      PurchaseUnit? unit;
      int? piecesPerPack;
      // Whole decimal counts are valid OCR output; a fractional suffix must
      // never become a separate quantity (for example, 2.50 becoming 50).
      final packCount = RegExp(
        r'(?<![\d.])\b(\d+)(?:\.0+)?\s*(?:packs?|pk)\b',
        caseSensitive: false,
      ).firstMatch(description);
      final pieceCount = RegExp(
        r'(?<![\d.])\b(\d+)(?:\.0+)?\s*(?:pcs?|pieces?)\b(?!\s*(?:/|per)\s*(?:pack|pk))',
        caseSensitive: false,
      ).firstMatch(description);
      final conversion = RegExp(
        r'(?<![\d.])\b(\d+)(?:\.0+)?\s*(?:pcs?|pieces?)\s*(?:/|per)\s*(?:pack|pk)\b',
        caseSensitive: false,
      ).firstMatch(description);
      if (packCount != null) {
        quantity = parseQuantity(packCount.group(1)!);
        unit = PurchaseUnit.pack;
        if (conversion != null) {
          piecesPerPack = parseQuantity(conversion.group(1)!);
        }
      } else if (pieceCount != null) {
        quantity = parseQuantity(pieceCount.group(1)!);
        unit = PurchaseUnit.piece;
        piecesPerPack = 1;
      } else {
        final leading = RegExp(
          r'^(\d{1,4})(?:\.0+)?\s+(?:[x×]\s+)?(?=[a-z])',
          caseSensitive: false,
        ).firstMatch(description);
        if (leading != null) {
          quantity = parseQuantity(leading.group(1)!);
          description = description.substring(leading.end).trim();
        }
      }
      final warnings = <String>['Confirm the exact brand, variant and size.'];
      final multipleAmounts = RegExp(
        r'\b\d[\d,]*\.\d{2}\b',
      ).allMatches(description).isNotEmpty;
      if (multipleAmounts) {
        warnings.add(
          'Multiple prices appear on this row. Confirm the total line amount, not the unit price.',
        );
      }
      if (quantity == null) warnings.add('Confirm the quantity purchased.');
      if (unit == null) {
        warnings.add('Confirm whether the quantity is pieces or packs.');
      }
      if (unit == PurchaseUnit.pack && piecesPerPack == null) {
        warnings.add('Confirm the pieces in each pack.');
      }
      draft.lines.add(
        ParsedLineItem(
          description: description,
          quantity: quantity,
          unit: unit,
          piecesPerPack: piecesPerPack,
          grossAmountCents: multipleAmounts ? null : cents,
          warnings: warnings,
        ),
      );
    }
    if (draft.purchasedAt == null) {
      draft.warnings.add('Choose and confirm the purchase date.');
    }
    if (draft.lines.isEmpty) {
      draft.warnings.add(
        'No complete item rows were recognized. Add items using the original receipt.',
      );
    }
    draft.warnings.add(
      'Check all extracted fields against the original receipt before saving.',
    );
    return draft;
  }

  bool _metadata(String text) => RegExp(
    r'\b(?:sub\s*total|vat|tax|cash|change|tender|payment|balance|total|amount\s+due|receipt|invoice|tel|phone)\b',
    caseSensitive: false,
  ).hasMatch(text);

  bool _supplierCandidate(String text) =>
      RegExp(r'[a-z]', caseSensitive: false).hasMatch(text) &&
      !RegExp(
        r'^(?:official|sales|cash|tax|receipt|invoice|transaction|date|time|tin|vat|tel|phone|address|branch|page|qty|quantity|description|item|total)\b|\b(?:street|barangay|brgy|avenue|road|city)\b',
        caseSensitive: false,
      ).hasMatch(text) &&
      !RegExp(r'\d{1,2}[/\-]\d{1,2}').hasMatch(text) &&
      !RegExp(r'\d+\.\d{2}\s*$').hasMatch(text);

  /// Combine ordered photos as one draft. Matching suffix/prefix rows remain
  /// visible and unresolved: identical purchases can be legitimate, so only
  /// the owner can decide whether a row is an overlapping photo duplicate.
  ReceiptDraft parsePages({required List<ReceiptOcrPage> pages}) {
    if (pages.isEmpty || pages.length > maxReceiptPages) {
      throw const ValidationException('Choose 1 to 20 ordered receipt photos.');
    }
    final drafts = pages
        .map(
          (page) => parse(
            imagePath: page.imagePath,
            recognitionImagePath: page.recognitionImagePath,
            textLines: page.textLines,
          ),
        )
        .toList();
    if (pages.length == 1) return drafts.single;
    final result = ReceiptDraft(
      imagePath: pages.first.imagePath,
      imagePaths: pages.map((page) => page.imagePath).toList(),
      textLines: pages.expand((page) => page.textLines).toList(),
      rawText: drafts.indexed
          .map((entry) => '--- Photo ${entry.$1 + 1} ---\n${entry.$2.rawText}')
          .join('\n\n'),
    );
    final names = drafts
        .map((draft) => draft.supplierName.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (names.isNotEmpty) result.supplierName = names.first;
    if (names.map((name) => name.toLowerCase()).toSet().length > 1) {
      result.supplierName = '';
      result.warnings.add(
        'Supplier headings differ between photos. Confirm that all pages belong to one receipt and enter the supplier.',
      );
    }
    final dates = drafts
        .map((draft) => draft.purchasedAt)
        .whereType<DateTime>()
        .toList();
    if (dates.isNotEmpty) {
      result.purchasedAt = dates.first;
      result.hasPurchaseTime = drafts
          .firstWhere((draft) => draft.purchasedAt != null)
          .hasPurchaseTime;
    }
    if (dates.map((date) => (date.year, date.month, date.day)).toSet().length >
        1) {
      result.purchasedAt = null;
      result.hasPurchaseTime = false;
      result.warnings.add(
        'Purchase dates differ between photos. Check the receipt pages before confirming a date.',
      );
    }
    final numbers = drafts
        .map((draft) => draft.receiptNumber)
        .where((number) => number.isNotEmpty)
        .toSet();
    if (numbers.length == 1) result.receiptNumber = numbers.single;
    if (numbers.length > 1) {
      result.warnings.add(
        'Receipt numbers differ between photos. Check that these pages belong to one receipt.',
      );
    }
    // Last-page total is evidence only; differing page subtotals remain visible.
    for (final draft in drafts) {
      if (draft.detectedTotalCents != null) {
        result.detectedTotalCents = draft.detectedTotalCents;
      }
    }
    for (var page = 0; page < drafts.length; page++) {
      final current = drafts[page].lines;
      for (final line in current) {
        line.sourcePage = page;
      }
      if (page > 0) {
        final previous = drafts[page - 1].lines;
        var overlap = 0;
        for (
          var length = 1;
          length <= previous.length && length <= current.length;
          length++
        ) {
          var equal = true;
          for (var index = 0; index < length; index++) {
            if (!_samePurchase(
              previous[previous.length - length + index],
              current[index],
            )) {
              equal = false;
              break;
            }
          }
          if (equal) overlap = length;
        }
        for (var index = 0; index < overlap; index++) {
          current[index].possibleDuplicateOf =
              previous[previous.length - overlap + index].id;
        }
      }
      result.lines.addAll(current);
      result.warnings.addAll(
        drafts[page].warnings.map((warning) => 'Photo ${page + 1}: $warning'),
      );
    }
    return result;
  }

  bool _samePurchase(ParsedLineItem a, ParsedLineItem b) =>
      a.grossAmountCents != null &&
      a.grossAmountCents == b.grossAmountCents &&
      _overlapDescription(a) == _overlapDescription(b) &&
      a.quantity == b.quantity &&
      a.unit == b.unit &&
      a.piecesPerPack == b.piecesPerPack;

  String _overlapDescription(ParsedLineItem line) {
    var description = line.description.toLowerCase().trim();
    if (line.quantity != null && line.unit != null) {
      final units = line.unit == PurchaseUnit.pack
          ? r'(?:packs?|pk)'
          : r'(?:pcs?|pieces?)';
      final pair = '${line.quantity}(?:\\.0+)?\\s*$units';
      // OCR can place the purchased quantity before or after the description.
      // Remove only that known edge pair; product size/variant numbers remain.
      description = description
          .replaceFirst(RegExp('^$pair\\b\\s*'), '')
          .replaceFirst(RegExp('\\s+\\b$pair\\s*\$'), '');
    }
    // Punctuation differences only suggest review; neither row is discarded.
    return description.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  DateTime? _date(String text) {
    final iso = RegExp(
      r'\b(20\d{2})[/\-](\d{1,2})[/\-](\d{1,2})\b',
    ).firstMatch(text);
    if (iso != null) {
      return _validDate(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }
    final named = RegExp(
      r'\b(\d{1,2})\s*[- /]?\s*(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[a-z]*\s*[- /]?\s*(20\d{2})\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (named != null) {
      final month =
          [
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
          ].indexOf(named.group(2)!.toUpperCase()) +
          1;
      return _validDate(
        int.parse(named.group(3)!),
        month,
        int.parse(named.group(1)!),
      );
    }
    final separated = RegExp(
      r'\b(\d{1,2})[/\-](\d{1,2})[/\-](20\d{2})\b',
    ).firstMatch(text);
    if (separated == null) return null;
    final first = int.parse(separated.group(1)!);
    final second = int.parse(separated.group(2)!);
    final year = int.parse(separated.group(3)!);
    if (first > 12) return _validDate(year, second, first);
    if (second > 12) return _validDate(year, first, second);
    return null;
  }

  DateTime? _validDate(int year, int month, int day) {
    final result = DateTime(year, month, day);
    return result.year == year && result.month == month && result.day == day
        ? result
        : null;
  }

  (int, int, int)? _time(String text) {
    final match = RegExp(
      r'\b(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)?\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final second = int.parse(match.group(3) ?? '0');
    final meridiem = match.group(4)?.toUpperCase();
    if (meridiem != null) {
      if (hour < 1 || hour > 12) return null;
      hour = hour % 12 + (meridiem == 'PM' ? 12 : 0);
    }
    if (hour > 23 || minute > 59 || second > 59) return null;
    return (hour, minute, second);
  }
}
