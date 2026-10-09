import '../models/models.dart';
import 'receipt_numeric_row.dart';

/// Reconstruct printed rows from local OCR bounds. Header-labeled columns
/// identify totals; unlabeled pairs need explicit count and exact arithmetic.
List<String> prepareReceiptRows(List<OcrTextLine> lines) {
  final rows = _alignedCells(_layoutCells(lines));
  final output = <String>[];
  double? quantityX, amountX, unitPriceX, descriptionX;
  bool pieceUnits = false;
  bool hasTrailingTotal = false;
  bool quantityFollowsDescription = false;
  for (var index = 0; index < rows.length; index++) {
    final cells = rows[index];
    final text = resolveAtPrice(
      cells.map((cell) => cell.text).join(' ').trim(),
    );
    final header =
        RegExp(
          r'\b(?:description|item|product)\b',
          caseSensitive: false,
        ).hasMatch(text) &&
        RegExp(
          r'\b(?:qty|quantity|amount|price|total)\b',
          caseSensitive: false,
        ).hasMatch(text);
    if (header) {
      quantityX = amountX = unitPriceX = descriptionX = null;
      hasTrailingTotal = RegExp(
        r'\b(?:amount|total|extended)\s*$',
        caseSensitive: false,
      ).hasMatch(text);
      final qtyLabel = RegExp(
        r'\b(?:qty|quantity)\b',
        caseSensitive: false,
      ).firstMatch(text);
      final descLabel = RegExp(
        r'\b(?:description|item|product)\b',
        caseSensitive: false,
      ).firstMatch(text);
      quantityFollowsDescription =
          qtyLabel != null &&
          descLabel != null &&
          qtyLabel.start > descLabel.start;
      pieceUnits = RegExp(
        r'\b(?:qty|quantity)\s*\(?\s*(?:pcs|pieces)\b',
        caseSensitive: false,
      ).hasMatch(text);
      for (final cell in cells) {
        final label = cell.text.toLowerCase().trim();
        if (RegExp(r'^(?:qty|quantity)\b').hasMatch(label)) {
          quantityX = cell.left;
          pieceUnits =
              pieceUnits || RegExp(r'\b(?:pcs|pieces)\b').hasMatch(label);
        }
        if (RegExp(
          r'^(?:amount|line total|total|extended)\b',
        ).hasMatch(label)) {
          amountX = cell.left;
        }
        if (RegExp(r'^(?:unit price|price)\b').hasMatch(label)) {
          unitPriceX = cell.left;
        }
        if (RegExp(r'^(?:description|item|product)\b').hasMatch(label)) {
          descriptionX = cell.left;
        }
      }
      output.add(text);
      continue;
    }
    if (amountX != null &&
        descriptionX != null &&
        amountX != descriptionX &&
        cells.length > 1 &&
        !RegExp(
          r'^(?:total|subtotal|grand|cash|change|vat|tax|discount|amount due)\b',
          caseSensitive: false,
        ).hasMatch(text)) {
      final columns = <(String, double)>[
        ('description', descriptionX),
        ('amount', amountX),
        if (quantityX != null) ('quantity', quantityX),
        if (unitPriceX != null) ('unitPrice', unitPriceX),
      ];
      final values = <String, List<String>>{};
      final ordered = List<(String, double)>.of(columns)
        ..sort((a, b) => a.$2.compareTo(b.$2));
      final descriptionColumn = ordered.indexWhere(
        (column) => column.$1 == 'description',
      );
      final descriptionStart = descriptionColumn == 0
          ? double.negativeInfinity
          : (ordered[descriptionColumn - 1].$2 + descriptionX) / 2;
      final descriptionEnd = descriptionColumn == ordered.length - 1
          ? double.infinity
          : ordered[descriptionColumn + 1].$2;
      for (final cell in cells) {
        // A description spans the space before the next numeric column. Using
        // only the nearest heading would misclassify long names and sizes.
        if (cell.left >= descriptionStart &&
            cell.left < descriptionEnd - cell.height * .5) {
          values.putIfAbsent('description', () => []).add(cell.text);
          continue;
        }
        final sorted = List<(String, double)>.of(columns)
          ..sort(
            (a, b) =>
                (a.$2 - cell.left).abs().compareTo((b.$2 - cell.left).abs()),
          );
        values.putIfAbsent(sorted.first.$1, () => []).add(cell.text);
      }
      final description = values['description']?.join(' ') ?? '';
      final amount = values['amount']?.join(' ') ?? '';
      final quantity = values['quantity']?.join(' ') ?? '';
      if (RegExp(r'[a-z]', caseSensitive: false).hasMatch(description) &&
          _money(amount) != null) {
        final wholeQuantity = RegExp(r'^\d+(?:\.0+)?$').hasMatch(quantity);
        output.add(
          '${wholeQuantity ? '${quantity.replaceFirst(RegExp(r'\.0+$'), '')}${pieceUnits ? ' pcs' : ' x'} ' : ''}$description ${_money(amount)}',
        );
        continue;
      }
    }
    // Total labels may occupy a separate line from their amount.
    if (RegExp(r'^(?:grand\s+total|total(?:\s+(?:due|amount|sales))?|amount\s+(?:due|paid))\s*(?:PHP|₱)?\s*:?$',
        caseSensitive: false).hasMatch(text) && index + 1 < rows.length &&
        _nearby(cells, rows[index + 1])) {
      final value = _money(rows[index + 1].map((cell) => cell.text).join(' '));
      if (value != null) {
        output.add('$text $value');
        index++;
        continue;
      }
    }
    // Some POS layouts print quantity/prices before the product. Only bind
    // an explicit count row to an adjacent description; never skip a row.
    final numeric = receiptNumericRow(text);
    if (numeric != null && index + 1 < rows.length) {
      final next = rows[index + 1].map((cell) => cell.text).join(' ').trim();
      if (_descriptionOnly(next) && _nearby(cells, rows[index + 1])) {
        final amount = RegExp(r'\d[\d,]*\.\d{2}').firstMatch(numeric)!;
        output.add(
          '${numeric.substring(0, amount.start)}$next ${numeric.substring(amount.start)}',
        );
        index++;
        continue;
      }
    }
    // Printed descriptions commonly occupy the line above their quantity/prices.
    // Only join immediately adjacent rows whose second row is purely numeric.
    if (index + 1 < rows.length &&
        _descriptionOnly(text) &&
        _nearby(cells, rows[index + 1])) {
      final next = rows[index + 1].map((cell) => cell.text).join(' ').trim();
      // A missing count must not discard the preceding product description.
      // Preserve unfamiliar unit text; only the parser's known units infer units.
      if (RegExp(r'^(?:\d+\s+)?(?![x×]\b)[A-ZČ]{1,3}\s+\d[\d,]*\.\d{2}\s*(?:VE|[A-Z*])?$',
          caseSensitive: false).hasMatch(next)) {
        output.add('$text $next');
        index++;
        continue;
      }
      if (RegExp(r'^\d+(?:\.0+)?\s*(?:pcs?|pieces?|packs?|pk|[x×])$', caseSensitive: false).hasMatch(next)) {
        output.add('$text $next');
        index++;
        continue;
      }
      final resolved = receiptNumericRow(next);
      if (resolved != null && !hasTrailingTotal) {
        final amount = RegExp(r'\d[\d,]*\.\d{2}').firstMatch(resolved)!;
        output.add(
          RegExp(r'\b[x×]\b', caseSensitive: false).hasMatch(resolved.substring(0, amount.start))
              ? '${resolved.substring(0, amount.start)}$text ${resolved.substring(amount.start)}'
              : '$text $resolved',
        );
        index++;
        continue;
      }
      final explicitUnit = RegExp(
        r'^(\d+(?:\.0+)?)\s*(packs?|pk|pcs?|pieces?)\s+(\d[\d,]*\.\d{2}(?:\s+\d[\d,]*\.\d{2})*)\s*(?:VE|[A-Z*])?$',
        caseSensitive: false,
      ).firstMatch(next);
      if (explicitUnit != null) {
        final prices = explicitUnit.group(3)!.trim().split(RegExp(r'\s+'));
        output.add(
          '$text ${explicitUnit.group(1)!.replaceFirst(RegExp(r'\.0+$'), '')} ${explicitUnit.group(2)} ${hasTrailingTotal ? prices.last : prices.join(' ')}',
        );
        index++;
        continue;
      }
      final match = RegExp(
        r'^(\d+(?:\.0+)?)\s+(?:[x×]\s+)?(?:\d[\d,]*\.\d{2}\s+)?(\d[\d,]*\.\d{2})\s*(?:VE|[A-Z*])?$',
        caseSensitive: false,
      ).firstMatch(next);
      if (match != null) {
        final prices = RegExp(r'\d[\d,]*\.\d{2}').allMatches(next).length;
        // Without a total-column header, preserve both numbers for explicit review.
        final quantity = match.group(1)!.replaceFirst(RegExp(r'\.0+$'), '');
        final pricesText = RegExp(r'\d[\d,]*\.\d{2}')
            .allMatches(next.substring(match.group(1)!.length))
            .map((price) => price.group(0))
            .join(' ');
        output.add(
          '$quantity x $text ${prices > 1 && !hasTrailingTotal ? pricesText : match.group(2)}',
        );
        index++;
        continue;
      }
      if (_money(next) != null &&
          RegExp(
            r'\b(?:pcs?|pieces?|packs?|pk)\b|\b\d+(?:\.\d+)?\s*(?:g|kg|ml|l|oz|s)\b',
            caseSensitive: false,
          ).hasMatch(text)) {
        output.add('$text ${_money(next)}');
        index++;
        continue;
      }
    }
    if (hasTrailingTotal &&
        RegExp(r'[a-z]', caseSensitive: false).hasMatch(text) &&
        !RegExp(
          r'^(?:total|subtotal|grand|cash|change|vat|tax|discount|amount due)\b',
          caseSensitive: false,
        ).hasMatch(text)) {
      final quantityFields = RegExp(
        r'(?<![\d.])\b\d+(?:\.\d+)?\s*(?:packs?|pk|pcs?|pieces?)\b|^\d+(?:\.\d+)?\s+(?:[x×]\s+)?(?=[a-z])',
        caseSensitive: false,
      ).allMatches(text).toList();
      // Quantity counts can have the same decimal format as prices. Retain
      // their original text, including unsupported fractions, for correction.
      final prices = RegExp(r'(?<![\w.])\d[\d,]*\.\d{2}(?![\w.])')
          .allMatches(text)
          .where(
            (price) => !quantityFields.any(
              (quantity) =>
                  price.start >= quantity.start && price.end <= quantity.end,
            ),
          )
          .toList();
      if (prices.isNotEmpty &&
          _money(text.substring(prices.last.start)) != null) {
        var description = text.substring(0, prices.first.start).trim();
        if (quantityFollowsDescription) {
          final qty = RegExp(r'\s+(\d+)(?:\.0+)?$').firstMatch(description);
          if (qty != null) {
            description =
                '${qty.group(1)}${pieceUnits ? ' pcs' : ' x'} ${description.substring(0, qty.start)}';
          }
        }
        output.add('$description ${prices.last.group(0)}');
        continue;
      }
    }
    // Distinct bounded quantity cells provide evidence that a numeric prefix
    // is a count. An unlabeled number inside one OCR line may be a brand/code.
    if (cells.length > 1 &&
        RegExp(r'^\d{1,4}(?:\.0+)?$').hasMatch(cells.first.text) &&
        !RegExp(
          r'^\d+\s+item|^\d+\s+(?:pcs?|pieces?|packs?|pk|[x×])\b|^(?:7\s+up|100\s+plus)\b',
          caseSensitive: false,
        ).hasMatch(text) &&
        RegExp(r'[a-z]', caseSensitive: false).hasMatch(cells[1].text)) {
      output.add(
        '${cells.first.text} x ${cells.skip(1).map((cell) => cell.text).join(' ')}',
      );
    } else {
      output.add(text);
    }
  }
  return output;
}

String? _money(String text) {
  final match = RegExp(
    r'^(?:₱|PHP\s*)?(\d[\d,]*\.\d{2})\s*(?:VE|[A-Z*])?$',
    caseSensitive: false,
  ).firstMatch(text.trim());
  return match?.group(1);
}

bool _descriptionOnly(String text) =>
    RegExp(r'[a-z]', caseSensitive: false).hasMatch(text) &&
    !RegExp(r'\d+\.\d{2}').hasMatch(text) &&
    !RegExp(
      r'^\d+\s+(?:x\s+)?item|^(?:total|subtotal|grand|cash|change|vat|tax|discount|amount|date|time|receipt|invoice|tel|phone|tin|address|official|page)\b',
      caseSensitive: false,
    ).hasMatch(text);

List<List<OcrTextLine>> _alignedCells(List<OcrTextLine> lines) {
  if (lines.every((line) => line.height <= 0)) {
    return lines.map((line) => [line]).toList();
  }
  final sorted = List<OcrTextLine>.of(lines)
    ..sort((a, b) {
      // Build description/count anchors before attaching price cells. A price
      // slightly above its label must not join the preceding product merely
      // because that product was the only row seen so far.
      bool price(OcrTextLine line) => RegExp(
        r'^(?:PHP\s*)?[\d.,₱\s]+(?:VE|V|E|Z|€)?$', caseSensitive: false,
      ).hasMatch(line.text.trim()) && RegExp(r'[.,]|[VEZ€]$', caseSensitive: false).hasMatch(line.text.trim());
      final type = (price(a) ? 1 : 0).compareTo(price(b) ? 1 : 0);
      return type != 0 ? type : a.top.compareTo(b.top);
    });
  final rows = <List<OcrTextLine>>[];
  for (final line in sorted) {
    List<OcrTextLine>? target;
    var nearest = double.infinity;
    for (final row in rows.reversed) {
      final anchor = row.first;
      final distance =
          (_baselineAt(anchor, line.left + line.width / 2) - (line.top + line.height / 2))
              .abs();
      final height = anchor.height < line.height ? anchor.height : line.height;
      // Permit modest baseline drift over a wide receipt, capped at half a
      // text height so neighboring rows cannot gain an unbounded allowance.
      final drift = (anchor.left - line.left).abs() * .03;
      final tolerance =
          height * .5 + (drift < height * .5 ? drift : height * .5);
      // Two lines occupying the same horizontal column are distinct printed
      // rows. Choose the closest baseline, not the first tolerant row: skewed
      // right-hand prices can otherwise attach to the next product.
      final overlapsColumn = row.any((cell) {
        if (cell.width <= 0 || line.width <= 0) return false;
        final start = cell.left > line.left ? cell.left : line.left;
        final end = cell.left + cell.width < line.left + line.width
            ? cell.left + cell.width
            : line.left + line.width;
        final minWidth = cell.width < line.width ? cell.width : line.width;
        return end - start > minWidth * .5;
      });
      final tooFarAbove = anchor.top - line.top > line.height * .35;
      if (!tooFarAbove && !overlapsColumn &&
          line.height > 0 &&
          anchor.height > 0 &&
          distance <= tolerance &&
          distance < nearest) {
        target = row;
        nearest = distance;
      }

    }
    if (target == null) {
      rows.add([line]);
    } else {
      target.add(line);
    }
  }
  rows.sort((a, b) => a.first.top.compareTo(b.first.top));
  for (final row in rows) {
    row.sort((a, b) => a.left.compareTo(b.left));
  }
  return rows;
}

List<OcrTextLine> _layoutCells(List<OcrTextLine> lines) {
  final hasItemTable = _alignedCells(lines).any((row) {
    final text = row.map((line) => line.text).join(' ');
    return RegExp(r'\b(?:description|item|product)\b', caseSensitive: false).hasMatch(text) &&
        RegExp(r'\b(?:qty|quantity|amount|price|total)\b', caseSensitive: false).hasMatch(text);
  });
  // Keep complete product descriptions outside labeled tables; tokenizing an
  // unlabeled description can split numeric brands and wrapped product names.
  if (!hasItemTable) return lines;
  return [
    for (final line in lines)
      if (line.tokens.isEmpty)
        line
      else
        for (final token in line.tokens)
          OcrTextLine(
            text: token.text,
            left: token.left,
            top: token.top,
            width: token.width,
            height: token.height,
          ),
  ];
}

String recognizedReceiptText(List<OcrTextLine> lines) => _alignedCells(
  lines,
).map((row) => row.map((cell) => cell.text).join(' ')).join('\n');

// Without bounds (synthetic fixtures), printed adjacency is the only evidence.
// With bounds, a large blank area cannot attach a footer price to a product.
bool _nearby(List<OcrTextLine> first, List<OcrTextLine> second) {
  final a = first.first;
  final b = second.first;
  if (a.height <= 0 || b.height <= 0) return true;
  return b.top - (a.top + a.height) <= (a.height + b.height) * 1.5;
}

// Native word boxes provide the local printed slope across a description.
// Project that baseline to the price column, capped for modest camera skew.
double _baselineAt(OcrTextLine line, double x) {
  final tokens = line.tokens;
  if (tokens.length < 2) return line.top + line.height / 2;
  final first = tokens.first;
  final last = tokens.last;
  final startX = first.left + first.width / 2;
  final endX = last.left + last.width / 2;
  if (endX - startX < line.height * 2) return line.top + line.height / 2;
  final startY = first.top + first.height / 2;
  final endY = last.top + last.height / 2;
  final slope = ((endY - startY) / (endX - startX)).clamp(-.08, .08);
  return startY + (x - startX) * slope;
}
