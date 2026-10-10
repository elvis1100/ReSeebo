import '../models/models.dart';

/// Conservative identity matching for first scans. Complete catalog identities
/// must appear as whole tokens or one complete joined identity; fuzzy
/// abbreviations remain owner choices.
Product? exactProductMatch(String description, Iterable<Product> products) {
  String normalize(String value) {
    var text = value.toLowerCase().replaceAllMapped(
      RegExp(r'([a-z])(\d)'),
      (match) => '${match[1]} ${match[2]}',
    );
    text = text.replaceAllMapped(
      RegExp(r'\b(\d+(?:\.\d+)?)\s*(kg|g|l|ml|oz|pcs?|packs?|s)\b'),
      (match) {
        final unit = match[2]!;
        final amount = double.parse(match[1]!);
        final base = amount * (unit == 'kg' || unit == 'l' ? 1000 : 1);
        final normalizedUnit = unit == 'l' || unit == 'ml'
            ? 'ml'
            : unit == 'kg' || unit == 'g'
            ? 'g'
            : unit.startsWith('pc')
            ? 'pcs'
            : unit.startsWith('pack')
            ? 'pack'
            : unit;
        final sizeValue = base
            .toStringAsFixed(3)
            .replaceFirst(RegExp(r'\.?0+$'), '')
            .replaceAll('.', 'd');
        return '$sizeValue $normalizedUnit';
      },
    );
    return text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  final text = ' ${normalize(description)} ';
  final matches = products.where((product) {
    if (product.nameOnly) {
      if (product.name.trim().isEmpty || product.size.trim().isEmpty) {
        return false;
      }
      final name = normalize(product.name);
      final size = normalize(product.size);
      final identity = ' $name '.contains(' $size ') ? name : '$name $size';
      // Products entered with one full name have no separate identity fields.
      // Require the complete owner-entered name and size, not token subsets.
      return text.replaceAll(' ', '') == identity.replaceAll(' ', '');
    }
    if ([
      product.brand,
      product.variant,
      product.size,
    ].any((value) => value.trim().isEmpty)) {
      return false;
    }
    final expected = [product.brand, product.variant, product.size];
    final separateFields = expected.every(
      (value) => text.contains(' ${normalize(value)} '),
    );
    // OCR often joins brand/variant/size into one word. Permit whitespace
    // differences only when the entire printed identity matches; substring
    // similarity, missing identity fields and digit substitutions are unsafe.
    final completeJoinedIdentity =
        text.replaceAll(' ', '') ==
        normalize(expected.join(' ')).replaceAll(' ', '');
    if (!separateFields && !completeJoinedIdentity) {
      return false;
    }
    // Additional printed sizes conflict with the catalog identity even if one
    // size matches; combo packs need explicit review.
    final sizes = RegExp(
      r'\b\d+(?:d\d+)?\s+(?:g|ml|oz|pcs|pack|s)\b',
    ).allMatches(text).map((match) => match[0]).toSet();
    return sizes.length == 1;
  }).toList();
  return matches.length == 1 ? matches.single : null;
}
