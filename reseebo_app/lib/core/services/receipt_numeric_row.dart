import '../constants/formatters.dart';

/// Resolves an explicitly marked count and one/two monetary columns. Two
/// unlabeled columns require exact centavo arithmetic; no OCR digit repair or
/// rounding tolerance is applied. X establishes count, not pack conversion.
String? receiptNumericRow(String text) {
  final match = RegExp(
    r'^(\d+(?:\.0+)?)\s*(pcs?|pieces?|packs?|pk|po|pč|[x×])\s*\*?\s*((?:\d[\d,]*\.\d{2}\s*){1,2})\s*(VE|[\p{L}*])?$',
    caseSensitive: false,
    unicode: true,
  ).firstMatch(text.trim());
  if (match == null) return null;
  final quantity = int.tryParse(match[1]!.replaceFirst(RegExp(r'\.0+$'), ''));
  final prices = RegExp(
    r'\d[\d,]*\.\d{2}',
  ).allMatches(match[3]!).map((value) => value[0]!).toList();
  if (quantity == null || quantity <= 0) return null;
  final amounts = prices.map(parsePesos).toList();
  // Recognition may produce bad comma grouping or an out-of-range amount.
  // Keep that evidence unnormalized instead of throwing or hiding a bad price.
  if (amounts.any((amount) => amount == null)) return null;
  // OCR can confuse C with O/Č. The printed count is usable, but an unclear
  // unit must still be confirmed rather than silently becoming pieces.
  final marker = RegExp(r'^p[oč]$', caseSensitive: false).hasMatch(match[2]!)
      ? 'x'
      : match[2]!;
  final suffix = match[4] == null ? '' : ' ${match[4]}';
  if (prices.length == 2 && amounts.first! * quantity != amounts.last) {
    return '$quantity $marker ${prices.join(' ')}$suffix';
  }
  return '$quantity $marker ${prices.last}$suffix';
}

/// An @ price is explicitly a unit price. Preserve both amounts when their
/// relationship disagrees so the parser leaves the line amount unresolved.
String resolveAtPrice(String text) {
  final match = RegExp(
    r'^(\d+(?:\.0+)?)\s+(?:(pcs?|pieces?|packs?|pk|[x×])\s+)?(.+?)\s*@\s*(\d[\d,]*(?:\.\d{1,2})?)\s+(\d[\d,]*\.\d{2})\s*(VE|[\p{L}*])?$',
    caseSensitive: false,
    unicode: true,
  ).firstMatch(text);
  if (match == null) return text;
  final quantity = match[1]!.replaceFirst(RegExp(r'\.0+$'), '');
  final marker = match[2] ?? 'x';
  final unit = parsePesos(match[4]!);
  final total = parsePesos(match[5]!);
  final suffix = match[6] == null ? '' : ' ${match[6]}';
  if (unit == null || total == null || unit * int.parse(quantity) != total) {
    // Format integer unit prices as money too, retaining ambiguity downstream.
    return '$quantity $marker ${match[3]} ${(unit == null ? match[4]! : (unit / 100).toStringAsFixed(2))} ${match[5]}$suffix';
  }
  return '$quantity $marker ${match[3]} ${match[5]}$suffix';
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
