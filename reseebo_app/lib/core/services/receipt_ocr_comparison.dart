import '../models/models.dart';
import 'receipt_parser.dart';

/// Compares independently parsed OCR passes without mixing their coordinates.
/// The selected crop remains authoritative: original-only rows are never added.
class ReceiptOcrComparison {
  const ReceiptOcrComparison();

  void supplement(ReceiptDraft draft, List<ReceiptOcrPage> pages) {
    final parser = ReceiptParser();
    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final page = pages[pageIndex];
      if (page.originalTextLines.isEmpty) continue;
      final original = parser.parse(
        imagePath: page.imagePath,
        textLines: page.originalTextLines,
      );
      final selected = draft.lines
          .where((line) => line.sourcePage == pageIndex)
          .toList();
      for (final line in selected) {
        if (line.confirmed) continue;
        final key = _identity(line.description);
        if (key.isEmpty ||
            selected
                    .where((item) => _identity(item.description) == key)
                    .length !=
                1) {
          continue;
        }
        final candidates = original.lines
            .where((item) => _identity(item.description) == key)
            .toList();
        if (candidates.length != 1) continue;
        final other = candidates.single;
        final conflicts =
            _disagrees(line.quantity, other.quantity) ||
            _disagrees(line.grossAmountCents, other.grossAmountCents) ||
            (line.unit != null &&
                other.unit != null &&
                line.unit != other.unit) ||
            _disagrees(line.piecesPerPack, other.piecesPerPack);
        if (conflicts) {
          line.warnings.add(
            'Original and enhanced photo readings disagree. Check the printed quantity and amount.',
          );
          continue;
        }
        // An unresolved pair of printed prices is contradictory evidence, not
        // an absent field. A different pass must not silently resolve it.
        if (line.warnings.any(
              (warning) => warning.startsWith('Multiple prices'),
            ) ||
            other.warnings.any(
              (warning) => warning.startsWith('Multiple prices'),
            )) {
          continue;
        }
        var filled = false;
        if (!line.quantityEdited &&
            line.quantity == null &&
            other.quantity != null) {
          line.quantity = other.quantity;
          line.extractedQuantity = other.quantity;
          filled = true;
        }
        if (!line.amountEdited &&
            line.grossAmountCents == null &&
            other.grossAmountCents != null &&
            line.discountCents == other.discountCents) {
          line.grossAmountCents = other.grossAmountCents;
          line.extractedAmountCents = other.grossAmountCents;
          filled = true;
        }
        if (filled) {
          line.warnings.add(
            'A missing field was read from the original photo. Check it against the receipt.',
          );
        }
      }
    }
  }

  static bool _disagrees(int? first, int? second) =>
      first != null && second != null && first != second;

  // Preserve decimal punctuation so 1.5L cannot become the identity 15L.
  static String _identity(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9.]'), '');
}
