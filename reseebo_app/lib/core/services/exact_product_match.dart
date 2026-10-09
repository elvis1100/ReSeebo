import '../models/models.dart';

/// Conservative identity matching for first scans. Complete catalog identities
/// must appear as whole tokens; fuzzy abbreviations remain owner choices.
Product? exactProductMatch(String description, Iterable<Product> products) {
  String normalize(String value) {
    var text = value.toLowerCase();
    text = text.replaceAllMapped(RegExp(r'\b(\d+(?:\.\d+)?)\s*(kg|g|l|ml)\b'), (
      match,
    ) {
      final unit = match[2]!;
      final amount = double.parse(match[1]!);
      final base = amount * (unit == 'kg' || unit == 'l' ? 1000 : 1);
      return '${base.toStringAsFixed(3).replaceFirst(RegExp(r"\.?0+$"), "")} ${unit == 'l' || unit == 'ml' ? 'ml' : 'g'}';
    });
    return text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  final text = ' ${normalize(description)} ';
  final matches = products.where((product) {
    if (product.nameOnly ||
        [
          product.brand,
          product.variant,
          product.size,
        ].any((value) => value.trim().isEmpty)) {
      return false;
    }
    final expected = [product.brand, product.variant, product.size];
    if (!expected.every((value) => text.contains(' ${normalize(value)} '))) {
      return false;
    }
    // Additional printed sizes conflict with the catalog identity even if one
    // size matches; combo packs need explicit review.
    final sizes = RegExp(
      r'\b\d+\s+(?:g|ml)\b',
    ).allMatches(text).map((match) => match[0]).toSet();
    return sizes.length == 1;
  }).toList();
  return matches.length == 1 ? matches.single : null;
}
