import '../constants/formatters.dart';
import '../models/models.dart';

/// One isolated monetary cell. A single trailing letter is retained as a tax
/// marker, never used to repair digits; malformed/out-of-range money stays null.
class ReceiptMoneyEvidence {
  ReceiptMoneyEvidence(this.source) {
    final match = RegExp(
      r'^(?:₱\s*|PHP\s*|P\s*)?(\d[\d,]*\.\d{2})\s*(VE|[\p{L}*])?$',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(source.text.trim());
    rawAmount = match?[1];
    marker = match?[2];
    cents = rawAmount == null ? null : parsePesos(rawAmount!);
  }
  final OcrTextLine source;
  late final String? rawAmount;
  late final String? marker;
  late final int? cents;
}

/// Bounds and raw fields belong to one printed item, before monetary resolution.
/// Unknown count characters and conflicting prices remain evidence, not guesses.
class ReceiptItemEvidence {
  const ReceiptItemEvidence({
    required this.descriptions,
    required this.countSource,
    required this.rawCount,
    required this.rawUnit,
    required this.prices,
    required this.sources,
  });
  final List<OcrTextLine> descriptions;
  final OcrTextLine countSource;
  final String? rawCount;
  final String rawUnit;
  final List<ReceiptMoneyEvidence> prices;
  final Set<OcrTextLine> sources;

  ParsedLineItem resolve() {
    var description = descriptions.map((line) => line.text).join(' ').trim();
    // Long code-shaped prefixes are evidence separate from the editable name.
    // Do not strip short numerals, promotional counts, or numeric brands.
    final code = RegExp(
      r'^([\dDOIl]{7,14})\s+(?=\S*[a-z])',
      caseSensitive: false,
    ).firstMatch(description);
    if (code != null) description = description.substring(code.end).trim();
    final quantity = rawCount == null
        ? null
        : parseQuantity(rawCount!.replaceFirst(RegExp(r'\.0+$'), ''));
    final unit =
        RegExp(r'^(?:pcs?|pieces?)$', caseSensitive: false).hasMatch(rawUnit)
        ? PurchaseUnit.piece
        : RegExp(r'^(?:packs?|pk)$', caseSensitive: false).hasMatch(rawUnit)
        ? PurchaseUnit.pack
        : null;
    final warnings = <String>['Confirm the exact brand, variant and size.'];
    int? amount;
    // Two columns have already been associated geometrically. Their economic
    // relationship is resolved once, without rebuilding and reparsing a string.
    if (prices.length == 2 && prices.every((price) => price.cents != null)) {
      final first = prices.first.cents!;
      final last = prices.last.cents!;
      if (quantity != null ? quantity * first == last : first == last) {
        amount = last;
      }
    }
    if (amount == null) {
      warnings.add(
        'Multiple prices appear on this row. Confirm the total line amount, not the unit price.',
      );
    }
    if (quantity == null) warnings.add('Confirm the quantity purchased.');
    if (unit == null) {
      warnings.add('Confirm whether the quantity is pieces or packs.');
    } else if (unit == PurchaseUnit.pack) {
      warnings.add('Confirm the pieces in each pack.');
    }
    for (final price in prices) {
      final marker = price.marker;
      if (marker != null &&
          !RegExp(
            r'^(?:VE|V|E|Z|\*)$',
            caseSensitive: false,
          ).hasMatch(marker)) {
        warnings.add(
          'Unclear trailing price marker "$marker". Check the original receipt.',
        );
      }
    }
    return ParsedLineItem(
      description: description,
      printedItemCode: code?[1],
      quantity: quantity,
      extractedQuantity: quantity,
      unit: unit,
      piecesPerPack: unit == PurchaseUnit.piece ? 1 : null,
      grossAmountCents: amount,
      extractedAmountCents: amount,
      warnings: warnings,
    );
  }
}

/// Groups bounded description/count/two-price blocks. Returns only uniquely
/// owned blocks; other layouts retain the existing table/adjacency path. No
/// supplier names, fixed coordinates, totals, or catalog prices guide grouping.
List<ReceiptItemEvidence> groupReceiptItems(List<OcrTextLine> lines) {
  final bounded =
      lines.where((line) => line.height > 0 && line.width > 0).toList()
        ..sort((a, b) => a.top.compareTo(b.top));
  final groups = <ReceiptItemEvidence>[];
  final countPattern = RegExp(
    r'^(?:(\d+(?:\.0+)?|[IT|])\s*)?(pcs?|pieces?|packs?|pk|po|pč|[x×])\s*\*?\s*((?:\d[\d,]*\.\d{2}\s*){0,2})$',
    caseSensitive: false,
  );
  bool description(OcrTextLine line) =>
      countPattern.firstMatch(line.text.trim()) == null &&
      ReceiptMoneyEvidence(line).rawAmount == null &&
      RegExp(r'[a-z]', caseSensitive: false).hasMatch(line.text) &&
      !RegExp(r'\d+\.\d{2}').hasMatch(line.text) &&
      !_itemBoundary(line.text);

  for (final count in bounded) {
    final match = countPattern.firstMatch(count.text.trim());
    if (match == null) continue;
    final preceding = bounded
        .where(
          (line) =>
              line.top < count.top &&
              line.left <= count.left + count.height &&
              description(line),
        )
        .toList();
    if (preceding.isEmpty) continue;
    final name = preceding.last;
    if (count.top - (name.top + name.height) >
            (name.height + count.height) * 1.5 ||
        groups.any((group) => group.sources.contains(name))) {
      continue;
    }
    final following = bounded
        .where(
          (line) =>
              line.top > name.top &&
              line.left <= count.left + count.height &&
              description(line),
        )
        .toList();
    var nextTop = following.isEmpty ? double.infinity : following.first.top;
    for (final line in bounded) {
      if (line.top > name.top &&
          _itemBoundary(line.text) &&
          line.top < nextTop) {
        nextTop = line.top;
      }
    }
    // A count below the next description cannot be borrowed by the previous
    // item, even when arithmetic would happen to agree.
    if (count.top >= nextTop) continue;
    final sources = <OcrTextLine>{name, count};
    final names = <OcrTextLine>[name];
    for (final line in bounded) {
      if (line == name || !description(line)) continue;
      final gap = line.left - (name.left + name.width);
      if (gap >= -name.height * .2 &&
          gap <= name.height * 2 &&
          (line.top - name.top).abs() <= name.height * .6 &&
          line.top < count.top) {
        names.add(line);
        sources.add(line);
      }
    }
    final prices = <ReceiptMoneyEvidence>[];
    // Inline count/unit-price OCR still retains its own word bounds.
    for (final price in RegExp(r'\d[\d,]*\.\d{2}').allMatches(match[3]!)) {
      final raw = price[0]!;
      final tokens = count.tokens.where((token) => token.text == raw).toList();
      final token = tokens.length == 1 ? tokens.single : null;
      prices.add(
        ReceiptMoneyEvidence(
          OcrTextLine(
            text: raw,
            left: token?.left ?? count.left + count.width * .6,
            top: token?.top ?? count.top,
            width: token?.width ?? count.width * .4,
            height: token?.height ?? count.height,
          ),
        ),
      );
    }
    for (final line in bounded) {
      if (sources.contains(line) ||
          line.left <= count.left + count.height ||
          line.top < name.top + name.height * .4 ||
          line.top >= nextTop ||
          line.top > count.top + count.height * 1.5) {
        continue;
      }
      final price = ReceiptMoneyEvidence(line);
      // Retain damaged numeric cells so a readable unit price is not promoted
      // into a line amount just because the other column failed recognition.
      final damaged =
          RegExp(
            r"^[\d\s.,'’]+(?:\s*[\p{L}*])?$",
            unicode: true,
          ).hasMatch(line.text.trim()) &&
          RegExp(r"[.,'’]").hasMatch(line.text);
      if (price.rawAmount == null && !damaged) continue;
      prices.add(price);
      sources.add(line);
    }
    if (prices.length < 2) continue;
    prices.sort((a, b) => a.source.left.compareTo(b.source.left));
    // A second nearby baseline in the same column is ambiguous evidence, not
    // an additional price belonging to this item.
    if (prices.last.source.left - prices.first.source.left < count.height * 2 ||
        groups.any((group) => group.sources.any(sources.contains))) {
      continue;
    }
    groups.add(
      ReceiptItemEvidence(
        descriptions: List.unmodifiable(names),
        countSource: count,
        rawCount: match[1],
        rawUnit: match[2]!,
        prices: List.unmodifiable(prices),
        sources: Set.unmodifiable(sources),
      ),
    );
  }
  return groups;
}

// Footer/table labels are ownership barriers even when they contain no money.
// Their following amount/count cells cannot complete the preceding purchase.
bool _itemBoundary(String text) => RegExp(
  r'^(?:total|subtotal|grand|cash|change|vat|tax|discount|amount|date|time|receipt|invoice|tel|phone|tin|address|official|page|items|description|quantity|qty|sales|savings|tender|payment|balance|maya|visa|card|pos|serial|ptu|accred|cust|str|trx|ref)\b|^\d+\s+item(?:\(s\)|s)?\b',
  caseSensitive: false,
).hasMatch(text.trim());
