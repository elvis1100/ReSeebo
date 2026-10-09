import '../constants/formatters.dart';
import '../models/models.dart';
import '../errors/app_exception.dart';
import 'receipt_layout.dart';
import 'receipt_purchase_datetime.dart';

/// Layout heuristics provide editable suggestions, never confirmed purchases.
/// Unlabeled pack conversion and ambiguous dates stay owner decisions.
class ReceiptParser {
  final _purchaseDateTime = ReceiptPurchaseDateTime();
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
      ocrPages: [
        ReceiptOcrPage(
          imagePath: imagePath,
          recognitionImagePath: recognitionImagePath,
          textLines: List.of(textLines),
        ),
      ],
    );
    final purchase = _purchaseDateTime.suggest(
      recognizedReceiptText(textLines).split('\n'),
    );
    draft.purchasedAt = purchase.purchasedAt;
    draft.hasPurchaseTime = purchase.hasPurchaseTime;
    draft.warnings.addAll(purchase.warnings);
    final amountPattern = RegExp(
      r'(?:₱|PHP\s*)?(-?\d[\d,]*\.\d{2})\s*(?:[A-Z*])?\s*$',
      caseSensitive: false,
    );
    var reachedTotal = false;
    var inItemTable = false;
    for (var index = 0; index < rows.length; index++) {
      final text = rows[index].trim();
      if (text.isEmpty) continue;
      if (RegExp(
            r'\b(?:description|item|product)\b',
            caseSensitive: false,
          ).hasMatch(text) &&
          RegExp(
            r'\b(?:qty|quantity|price|amount)\b',
            caseSensitive: false,
          ).hasMatch(text)) {
        inItemTable = true;
      }
      if (draft.supplierName.isEmpty && index < 6 && _supplierCandidate(text)) {
        draft.supplierName = text;
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
      if (amountMatch == null) {
        if (!reachedTotal &&
            !_metadata(text) &&
            text != draft.supplierName &&
            (_likelyIncompleteItem(text) ||
                (inItemTable &&
                    RegExp(r'[a-z]', caseSensitive: false).hasMatch(text)))) {
          draft.lines.add(
            ParsedLineItem(
              description: text,
              warnings: [
                'This item row is incomplete. Check the original receipt and enter the missing fields.',
                'Confirm the exact brand, variant and size.',
                'Confirm the quantity, pieces or packs, and line amount.',
              ],
            ),
          );
        }
        continue;
      }
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
            'Possible discount ${amountMatch.group(1)}. Enter the final amount paid for the item; check it against the receipt total.';
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
      final printedDescription = description;
      int? quantity;
      PurchaseUnit? unit;
      int? piecesPerPack;
      RegExpMatch? leadingQuantity;
      var inferredLeadingQuantity = false;
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
        final explicitLeading = RegExp(
          r'^(\d{1,4})(?:\.0+)?\s+[x×]\s+(?=[a-z0-9])',
          caseSensitive: false,
        ).firstMatch(description);
        // Long prefixes are typically item codes. Recognizable numeric brands
        // retain their identity; other short naked counts remain reviewable.
        final numericBrand = RegExp(
          r'^(?:7\s+up|100\s+plus)\b',
          caseSensitive: false,
        ).hasMatch(description);
        final nakedLeading = numericBrand
            ? null
            : RegExp(
                r'^(\d{1,3})(?:\.0+)?\s+(?=[a-z])',
                caseSensitive: false,
              ).firstMatch(description);
        final leading = explicitLeading ?? nakedLeading;
        if (leading != null) {
          inferredLeadingQuantity = explicitLeading == null;
          leadingQuantity = leading;
          quantity = parseQuantity(leading.group(1)!);
          description = description.substring(leading.end).trim();
        }
      }
      final warnings = <String>['Confirm the exact brand, variant and size.'];
      if (inferredLeadingQuantity) {
        warnings.add(
          'Confirm that the leading number is a purchased quantity rather than a product name or code.',
        );
      }
      final quantityFields = [
        packCount,
        pieceCount,
        conversion,
        leadingQuantity,
      ].whereType<RegExpMatch>();
      // Printed whole-decimal counts are not monetary columns. Ignore only
      // their recognized field spans, retaining other prices for owner review.
      final multipleAmounts = RegExp(r'\b\d[\d,]*\.\d{2}\b')
          .allMatches(printedDescription)
          .any(
            (amount) => !quantityFields.any(
              (field) => amount.start >= field.start && amount.end <= field.end,
            ),
          );
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

  bool _metadata(String text) =>
      _purchaseDateTime.isMetadata(text) ||
      RegExp(
        r'^(?:date|time|tin|address|branch|page|qty|quantity|description|item|product)\b|\b(?:sub\s*total|vat|tax|cash|change|tender|payment|balance|total|amount\s+due|receipt|invoice|tel|phone)\b',
        caseSensitive: false,
      ).hasMatch(text);

  bool _likelyIncompleteItem(String text) =>
      RegExp(r'[a-z]', caseSensitive: false).hasMatch(text) &&
      RegExp(
        r'\b\d+(?:\.\d+)?\s*(?:g|kg|ml|l|oz|pcs?|pieces?|packs?|pk)\b',
        caseSensitive: false,
      ).hasMatch(text);

  bool _supplierCandidate(String text) =>
      !_purchaseDateTime.isMetadata(text) &&
      RegExp(r'[a-z]', caseSensitive: false).hasMatch(text) &&
      !RegExp(
        r'^(?:official|sales|cash|tax|receipt|invoice|transaction|date|time|tin|vat|tel|phone|address|branch|page|qty|quantity|description|item|total)\b|\b(?:street|barangay|brgy|avenue|road|city)\b',
        caseSensitive: false,
      ).hasMatch(text) &&
      !RegExp(r'\d{1,2}[./\-]\d{1,2}').hasMatch(text) &&
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
      ocrPages: List.of(pages),
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
    final purchase = _purchaseDateTime.suggest([
      for (final page in pages) ...[
        ...recognizedReceiptText(page.textLines).split('\n'),
        '',
      ],
    ]);
    result.purchasedAt = purchase.purchasedAt;
    result.hasPurchaseTime = purchase.hasPurchaseTime;
    result.warnings.addAll(purchase.warnings);
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
}
