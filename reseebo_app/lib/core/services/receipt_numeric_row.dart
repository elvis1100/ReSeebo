import '../constants/formatters.dart';

/// Resolves an explicitly marked count and one/two monetary columns. Two
/// unlabeled columns require exact centavo arithmetic; no OCR digit repair or
/// rounding tolerance is applied. X establishes count, not pack conversion.
String? receiptNumericRow(String text) {
  final match = RegExp(
    r'^(\d+(?:\.0+)?)\s*(pcs?|pieces?|packs?|pk|po|pč|[x×])\s*\*?\s*((?:\d[\d,]*\.\d{2}\s*){1,2})\s*(?:VE|V|E|Z|[A-Z*])?$',
    caseSensitive: false,
  ).firstMatch(text.trim());
  if (match == null) return null;
  final quantity = int.tryParse(match[1]!.replaceFirst(RegExp(r'\.0+$'), ''));
  final prices = RegExp(
    r'\d[\d,]*\.\d{2}',
  ).allMatches(match[3]!).map((value) => value[0]!).toList();
  if (quantity == null || quantity <= 0) return null;
  // OCR can confuse C with O/Č. The printed count is usable, but an unclear
  // unit must still be confirmed rather than silently becoming pieces.
  final marker = RegExp(r'^p[oč]$', caseSensitive: false).hasMatch(match[2]!)
      ? 'x'
      : match[2]!;
  if (prices.length == 2 &&
      parsePesos(prices.first)! * quantity != parsePesos(prices.last)) {
    return '$quantity $marker ${prices.join(' ')}';
  }
  return '$quantity $marker ${prices.last}';
}

/// An @ price is explicitly a unit price. Preserve both amounts when their
/// relationship disagrees so the parser leaves the line amount unresolved.
String resolveAtPrice(String text) {
  final match = RegExp(
    r'^(\d+)\s+(.+?)\s*@\s*(\d[\d,]*(?:\.\d{1,2})?)\s+(\d[\d,]*\.\d{2})\s*(?:VE|V|E|Z|[A-Z*])?$',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return text;
  final unit = parsePesos(match[3]!);
  final total = parsePesos(match[4]!);
  if (unit == null || total == null || unit * int.parse(match[1]!) != total) {
    // Format integer unit prices as money too, retaining ambiguity downstream.
    return '${match[1]} x ${match[2]} ${(unit == null ? match[3]! : (unit / 100).toStringAsFixed(2))} ${match[4]}';
  }
  return '${match[1]} x ${match[2]} ${match[4]}';
}

/// Printed columns agree only for a valid whole count and exact monetary values.
bool receiptAmountsAgree(String quantity, String price, String amount) {
  final count = int.tryParse(quantity.replaceFirst(RegExp(r'\.0+$'), ''));
  final unit = parsePesos(price);
  final total = parsePesos(amount);
  return count != null &&
      count > 0 &&
      unit != null &&
      total != null &&
      count * unit == total;
}
