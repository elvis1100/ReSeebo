import 'package:intl/intl.dart';
import '../models/models.dart';

final _currency = NumberFormat('#,##0.00', 'en_PH');
String pesos(num cents) => '₱${_currency.format(cents / 100)}';
String purchaseDate(DateTime date, {bool withTime = false}) => DateFormat(
  withTime ? 'd MMM yyyy · h:mm a' : 'd MMM yyyy',
  // English date symbols ship in intl's base library. Using that built-in
  // locale keeps first-launch formatting independent of initialization or I/O.
  'en_US',
).format(date.isUtc ? date.toLocal() : date);
String percent(num value) =>
    '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}%';

/// Accept decimal pesos without binary floating point conversion.
int? parsePesos(String input) {
  final cleaned = input.trim().replaceFirst(RegExp(r'^₱\s*'), '');
  if (!RegExp(
    r'^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$',
  ).hasMatch(cleaned)) {
    return null;
  }
  final parts = cleaned.replaceAll(',', '').split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null || whole > maxAmountCents ~/ 100) return null;
  final cents =
      whole * 100 +
      (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0')));
  return cents <= maxAmountCents ? cents : null;
}

String editablePesos(int? cents) =>
    cents == null ? '' : (cents / 100).toStringAsFixed(2);
double? parseMarkup(String input) {
  final value = double.tryParse(input.trim());
  return value != null && value.isFinite && value >= 0 && value <= 10000
      ? value
      : null;
}

int? parseQuantity(String input) {
  if (!RegExp(r'^\d+$').hasMatch(input.trim())) return null;
  final value = int.tryParse(input.trim());
  return value != null && value > 0 && value <= maxQuantity ? value : null;
}
