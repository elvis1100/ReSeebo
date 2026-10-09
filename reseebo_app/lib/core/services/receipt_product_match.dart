import '../models/models.dart';
import 'exact_product_match.dart';

/// Ranks receipt abbreviations against catalog identities without changing
/// printed sizes. Automatic selection requires every identity word, one exact
/// size, and a unique candidate; the owner still confirms the receipt line.
Product? receiptProductMatch(String description, Iterable<Product> products) {
  final catalog = products.toList();
  final exact = exactProductMatch(description, catalog);
  if (exact != null &&
      (_complete(description, exact) ||
          (_words(description).join() == _words(_identity(exact)).join() &&
              _identityDigits(description) ==
                  _identityDigits(_identity(exact)))) &&
      !_conflictingSize(description, exact)) {
    return exact;
  }
  final candidates = catalog.where((p) => _complete(description, p)).toList();
  return candidates.length == 1 ? candidates.single : null;
}

List<ProductMatchSuggestion> receiptProductSuggestions(
  String description,
  Iterable<Product> products,
) {
  final scored = <(Product, double)>[];
  final observed = _words(description);
  if (observed.isEmpty) return [];
  for (final product in products) {
    if (_conflictingSize(description, product)) continue;
    final expected = _words(_identity(product));
    if (expected.isEmpty) continue;
    final covered = expected
        .where((word) => observed.any((token) => _wordMatches(token, word)))
        .length;
    final score = _complete(description, product)
        ? 1.0
        : covered / expected.length;
    if (score >= .4) scored.add((product, score));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return scored
      .map(
        (entry) => ProductMatchSuggestion(
          product: entry.$1,
          reason: _complete(description, entry.$1)
              ? 'Receipt abbreviation and size agree'
              : 'Similar receipt name — check variant and size',
        ),
      )
      .toList();
}

String _identity(Product p) => p.nameOnly ? p.name : '${p.brand} ${p.variant}';

String _normalize(String value) => value.toLowerCase().replaceAllMapped(
  RegExp(r'(\d+(?:\.\d+)?)\s*(kg|ml|g|l|oz|pcs?|packs?|s)\b'),
  (m) {
    final unit = m[2]!;
    final amount =
        double.parse(m[1]!) * (unit == 'kg' || unit == 'l' ? 1000 : 1);
    return ' ${amount.toStringAsFixed(3)}${unit == 'kg'
        ? 'g'
        : unit == 'l'
        ? 'ml'
        : unit} ';
  },
);
Set<String> _sizes(String text) => RegExp(
  r'\d+\.\d{3}(?:g|ml|oz|pcs?|packs?|s)\b',
).allMatches(_normalize(text)).map((m) => m[0]!).toSet();
List<String> _words(String text) => _normalize(text)
    .replaceAll(RegExp(r'\d+\.\d{3}(?:g|ml|oz|pcs?|packs?|s)\b'), ' ')
    .replaceAll(RegExp(r'[^a-z]+'), ' ')
    .trim()
    .split(RegExp(r'\s+'))
    .where((s) => s.isNotEmpty)
    .toList();
bool _conflictingSize(String text, Product p) {
  final observed = _sizes(text);
  final expected = _sizes(p.size);
  return observed.isNotEmpty &&
      (expected.length != 1 || observed.any((s) => !expected.contains(s)));
}

String _identityDigits(String text) => _normalize(text)
    .replaceAll(RegExp(r'\d+\.\d{3}(?:g|ml|oz|pcs?|packs?|s)\b'), '')
    .replaceAll(RegExp(r'[^0-9]'), '');

bool _complete(String description, Product p) {
  final sizes = _sizes(description);
  if (sizes.length != 1 ||
      _sizes(p.size).length != 1 ||
      _conflictingSize(description, p)) {
    return false;
  }
  if (_identityDigits(description) != _identityDigits(_identity(p))) {
    return false;
  }
  final expected = _words(_identity(p));
  if (expected.length < 2) return false;
  final compact = _words(description).join();
  final memo = <String, bool>{};
  bool consume(int index, int offset) {
    if (index == expected.length) return offset == compact.length;
    final key = '$index:$offset';
    if (memo.containsKey(key)) return memo[key]!;
    final word = expected[index];
    for (var end = offset + 2; end <= compact.length; end++) {
      if (_wordMatches(compact.substring(offset, end), word) &&
          consume(index + 1, end)) {
        return memo[key] = true;
      }
    }
    // Store abbreviations such as BB stand for consecutive brand initials.
    if (index + 1 < expected.length &&
        offset + 2 <= compact.length &&
        compact.substring(offset, offset + 2) ==
            '${word[0]}${expected[index + 1][0]}' &&
        consume(index + 2, offset + 2)) {
      return memo[key] = true;
    }
    return memo[key] = false;
  }

  return consume(0, 0);
}

bool _wordMatches(String token, String word) {
  if (token == word) return true;
  if (token.length >= 3 && word.startsWith(token)) return true;
  final consonants = word.replaceAll(RegExp('[aeiou]'), '');
  if (token.length >= 3 && consonants == token) return true;
  if (token.length < 5 ||
      word.length < 5 ||
      (token.length - word.length).abs() > 1) {
    return false;
  }
  var i = 0;
  var j = 0;
  var edits = 0;
  while (i < token.length && j < word.length) {
    if (token[i] == word[j]) {
      i++;
      j++;
      continue;
    }
    if (++edits > 1) return false;
    if (token.length >= word.length) i++;
    if (word.length >= token.length) j++;
  }
  return edits + token.length - i + word.length - j <= 1;
}
