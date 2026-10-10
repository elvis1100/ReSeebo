import '../models/models.dart';
import 'pricing_service.dart';
import 'receipt_product_match.dart';

/// Pure local proposals on a private snapshot. Only confirmed history may be
/// passed here; inferred values never become extracted evidence or confirmation.
class ReceiptSuggestionService {
  ReceiptDraft suggest(
    ReceiptDraft draft, {
    required List<Product> products,
    required List<PurchaseRecord> confirmedHistory,
    required DateTime importedAt,
  }) {
    final result = draft.snapshot();
    if (result.supplierName.trim().isNotEmpty) {
      result.provenance.putIfAbsent(
        ReceiptMetadataField.supplier,
        () => _extracted('Supplier printed on receipt.'),
      );
    }
    if (result.dateManuallyEdited) {
      result.provenance[ReceiptMetadataField.purchasedAt] = _owner(
        'Owner chose the purchase date.',
      );
    } else if (result.purchasedAt != null) {
      result.provenance.putIfAbsent(
        ReceiptMetadataField.purchasedAt,
        () => _extracted('Purchase date printed on receipt.'),
      );
    } else if (result.dateCandidates.isEmpty &&
        !_metadataOwner(result, ReceiptMetadataField.purchasedAt)) {
      result.purchasedAt = DateTime(
        importedAt.year,
        importedAt.month,
        importedAt.day,
      );
      result.hasPurchaseTime = false;
      result.dateConfirmed = false;
      result.dateFromReceipt = false;
      result.provenance[ReceiptMetadataField.purchasedAt] = _assumed(
        'Import date assumed; confirm the purchase date.',
      );
    }
    for (final line in result.lines) {
      final wasConfirmed = line.confirmed;
      final previousQuantity = line.quantity;
      final previousUnit = line.unit;
      final previousPieces = line.piecesPerPack;
      final previousAmount = line.grossAmountCents;
      final previousProduct = line.productId;
      final previousOrigin = line.provenance[ReceiptSuggestionField.amount];
      bool acceptedProposalUnchanged() {
        final currentOrigin = line.provenance[ReceiptSuggestionField.amount];
        return wasConfirmed &&
            previousQuantity == line.quantity &&
            previousUnit == line.unit &&
            previousPieces == line.piecesPerPack &&
            previousAmount == line.grossAmountCents &&
            previousProduct == line.productId &&
            previousOrigin?.origin == currentOrigin?.origin &&
            previousOrigin?.sourcePurchaseId ==
                currentOrigin?.sourcePurchaseId &&
            previousOrigin?.sourceReceiptId == currentOrigin?.sourceReceiptId &&
            previousOrigin?.sourceSupplierId ==
                currentOrigin?.sourceSupplierId &&
            previousOrigin?.sourcePurchasedAt ==
                currentOrigin?.sourcePurchasedAt &&
            previousOrigin?.explanation == currentOrigin?.explanation;
      }

      _seed(line);
      final weighted = isWeighted(line);
      if (line.quantity == null &&
          !line.quantityEdited &&
          !_ownerField(line, ReceiptSuggestionField.quantity) &&
          !weighted) {
        line.quantity = 1;
        line.provenance[ReceiptSuggestionField.quantity] = _assumed(
          'One counted unit assumed; confirm quantity.',
        );
        line.confirmed = false;
      }
      if (line.unit == null &&
          !_ownerField(line, ReceiptSuggestionField.unit) &&
          !weighted) {
        line.unit = PurchaseUnit.piece;
        line.piecesPerPack = 1;
        line.provenance[ReceiptSuggestionField.unit] = _assumed(
          'Pieces assumed; confirm the purchase unit.',
        );
        line.provenance[ReceiptSuggestionField.piecesPerPack] = _assumed(
          'One piece per individual unit.',
        );
        line.confirmed = false;
      }
      if (line.productId == null &&
          !_ownerField(line, ReceiptSuggestionField.product)) {
        final match = receiptProductMatch(line.description, products);
        if (match != null) {
          line.productId = match.id;
          line.matchOrigin = 'Matched from receipt';
          line.provenance[ReceiptSuggestionField.product] = _calculated(
            'Unique exact catalog brand, variant and size.',
          );
          line.confirmed = false;
        }
      }
      final amountOrigin =
          line.provenance[ReceiptSuggestionField.amount]?.origin;
      if ((amountOrigin == ReceiptFieldOrigin.history ||
              (amountOrigin == ReceiptFieldOrigin.calculated &&
                  line.extractedUnitPriceCents != null)) &&
          !line.amountEdited &&
          !_ownerField(line, ReceiptSuggestionField.amount)) {
        line.grossAmountCents = null;
        line.provenance.remove(ReceiptSuggestionField.amount);
        line.confirmed = false;
      }
      if (line.grossAmountCents != null ||
          line.amountEdited ||
          _ownerField(line, ReceiptSuggestionField.amount) ||
          weighted ||
          _contradictory(line)) {
        continue;
      }
      final unitPrice = line.extractedUnitPriceCents;
      final quantity = line.quantity;
      if (unitPrice != null) {
        if (unitPrice <= 0 ||
            unitPrice > maxAmountCents ||
            quantity == null ||
            quantity <= 0 ||
            quantity > maxQuantity ||
            line.unit == null) {
          continue;
        }
        final cents = BigInt.from(unitPrice) * BigInt.from(quantity);
        final normalizedDiscount = line.normalizedDiscountCents;
        final discount = line.discountCents;
        if (cents > BigInt.from(maxAmountCents) ||
            normalizedDiscount < 0 ||
            normalizedDiscount > maxAmountCents ||
            discount < 0 ||
            discount > maxAmountCents - normalizedDiscount) {
          continue;
        }
        final receiptDiscount = normalizedDiscount + discount;
        if (BigInt.from(receiptDiscount) >= cents) continue;
        // Review folds the discount into its editable payable amount. Active
        // discount remains deducted by netAmountCents until preparation occurs.
        line.grossAmountCents = cents.toInt() - normalizedDiscount;
        line.provenance[ReceiptSuggestionField.amount] = _calculated(
          'Calculated from explicit receipt unit price $unitPrice centavos × $quantity purchased units.'
          '${receiptDiscount == 0 ? '' : ' Receipt discount $receiptDiscount centavos deducted once from payable amount.'}',
        );
        line.confirmed = acceptedProposalUnchanged();
        continue;
      }
      final product = products.where((p) => p.id == line.productId).firstOrNull;
      final pieces = line.totalPieces;
      if (product == null ||
          pieces == null ||
          pieces <= 0 ||
          line.quantity! > maxQuantity ||
          (line.piecesPerPack ?? 1) > maxQuantity) {
        continue;
      }
      final history = confirmedHistory
          .where(
            (p) =>
                p.productId == product.id &&
                p.quantity > 0 &&
                p.piecesPerPack > 0 &&
                p.netAmountCents > 0 &&
                p.netAmountCents <= maxAmountCents,
          )
          .toList();
      if (history.isEmpty) continue;
      final latest = PricingService.comparison(
        product,
        const StoreProfile(),
        history,
      ).latestPrices.map((row) => row.purchase).toList();
      final sameSupplier = latest
          .where((p) => p.supplier.id == result.supplierId)
          .firstOrNull;
      final source = sameSupplier ?? _latestOther(latest);
      final numerator =
          BigInt.from(source.netAmountCents) * BigInt.from(pieces);
      final denominator = BigInt.from(source.totalPieces);
      final cents =
          ((numerator * BigInt.two + denominator) ~/ (denominator * BigInt.two))
              .toInt();
      if (cents <= 0 ||
          cents + line.discountCents > maxAmountCents ||
          line.discountCents < 0) {
        continue;
      }
      line.grossAmountCents = cents + line.discountCents;
      line.provenance[ReceiptSuggestionField.amount] = ReceiptFieldProvenance(
        origin: ReceiptFieldOrigin.history,
        explanation:
            'Estimated from confirmed purchase at ${source.supplier.label} on ${source.purchasedAt.toIso8601String().split('T').first}; ${source.netAmountCents} centavos for ${source.totalPieces} pieces; scaled by known total pieces and rounded once to centavos.',
        sourcePurchaseId: source.id,
        sourceReceiptId: source.receiptId,
        sourceSupplierId: source.supplier.id,
        sourceSupplierName: source.supplier.label,
        sourcePurchasedAt: source.purchasedAt,
      );
      // Acceptance belongs to a particular proposal, independently of origin.
      line.confirmed = acceptedProposalUnchanged();
    }
    final totalOrigin = result.provenance[ReceiptMetadataField.total]?.origin;
    if (result.detectedTotalCents != null &&
        totalOrigin != ReceiptFieldOrigin.calculated) {
      result.provenance.putIfAbsent(
        ReceiptMetadataField.total,
        () => _extracted('Total printed on receipt.'),
      );
    } else if (!_metadataOwner(result, ReceiptMetadataField.total)) {
      final amounts = result.lines
          .where(
            (line) =>
                line.grossAmountCents != null &&
                line.grossAmountCents! > 0 &&
                line.grossAmountCents! <= maxAmountCents &&
                line.discountCents >= 0 &&
                line.discountCents < line.grossAmountCents!,
          )
          .toList();
      result.totalIsPartial = amounts.length != result.lines.length;
      result.detectedTotalCents = amounts.isEmpty
          ? null
          : amounts.fold<int>(0, (sum, line) => sum + line.netAmountCents!);
      result.provenance[ReceiptMetadataField.total] = _calculated(
        result.totalIsPartial
            ? 'Partial sum of complete line amounts; unresolved amounts omitted.'
            : 'Sum of complete line amounts.',
      );
    }
    return result;
  }

  /// Weight units remain unresolved until the owner explicitly supplies counts.
  static bool isWeighted(ParsedLineItem line) =>
      RegExp(
        r'(?<![a-z])(?:kg|kilograms?|kgs|weight|weighted)\b|\d+[.,](?!0+\b)\d+\s*(?:g|grams?|pcs?|pieces?|packs?|pk)\b',
        caseSensitive: false,
      ).hasMatch(line.description) ||
      line.warnings.any(
        (w) => RegExp(
          r'\b(?:weight|weighted|fractional)\b',
          caseSensitive: false,
        ).hasMatch(w),
      );
  bool _contradictory(ParsedLineItem line) => line.warnings.any(
    (w) => RegExp(
      r'multiple prices|contradict|conflict.*price|ambiguous.*amount|readings disagree',
      caseSensitive: false,
    ).hasMatch(w),
  );
  bool _ownerField(ParsedLineItem line, ReceiptSuggestionField field) =>
      line.provenance[field]?.origin == ReceiptFieldOrigin.ownerEdited;
  bool _metadataOwner(ReceiptDraft draft, ReceiptMetadataField field) =>
      draft.provenance[field]?.origin == ReceiptFieldOrigin.ownerEdited;
  void _seed(ParsedLineItem line) {
    void seed(ReceiptSuggestionField field, bool present, String explanation) {
      if (present) {
        line.provenance.putIfAbsent(field, () => _extracted(explanation));
      }
    }

    seed(
      ReceiptSuggestionField.description,
      line.description.isNotEmpty,
      'Description printed on receipt.',
    );
    seed(
      ReceiptSuggestionField.quantity,
      line.quantity != null,
      'Count extracted from receipt.',
    );
    seed(
      ReceiptSuggestionField.unit,
      line.unit != null,
      'Purchase unit extracted from receipt.',
    );
    seed(
      ReceiptSuggestionField.piecesPerPack,
      line.piecesPerPack != null,
      'Piece denominator from receipt or explicit counted unit.',
    );
    seed(
      ReceiptSuggestionField.amount,
      line.grossAmountCents != null,
      'Unambiguous line amount from receipt arithmetic.',
    );
    if (line.quantityEdited) {
      line.provenance[ReceiptSuggestionField.quantity] = _owner(
        'Owner entered or cleared quantity.',
      );
    }
    if (line.amountEdited) {
      line.provenance[ReceiptSuggestionField.amount] = _owner(
        'Owner entered or cleared amount.',
      );
    }
  }

  PurchaseRecord _latestOther(List<PurchaseRecord> latest) {
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    final incomplete = latest
        .where((p) => !p.hasPurchaseTime)
        .map((p) => day(p.purchasedAt))
        .toSet();
    latest.sort((a, b) {
      final byDay = day(b.purchasedAt).compareTo(day(a.purchasedAt));
      if (byDay != 0) return byDay;
      if (!incomplete.contains(day(a.purchasedAt))) {
        final byTime = b.purchasedAt.compareTo(a.purchasedAt);
        if (byTime != 0) return byTime;
      }
      final recorded = b.recordedAt.compareTo(a.recordedAt);
      if (recorded != 0) return recorded;
      if (a.recordedOrder > 0 && b.recordedOrder > 0) {
        final byReceipt = b.recordedOrder.compareTo(a.recordedOrder);
        if (byReceipt != 0) return byReceipt;
      }
      return b.sequence.compareTo(a.sequence);
    });
    return latest.first;
  }

  ReceiptFieldProvenance _extracted(String text) => ReceiptFieldProvenance(
    origin: ReceiptFieldOrigin.extracted,
    explanation: text,
  );
  ReceiptFieldProvenance _calculated(String text) => ReceiptFieldProvenance(
    origin: ReceiptFieldOrigin.calculated,
    explanation: text,
  );
  ReceiptFieldProvenance _assumed(String text) => ReceiptFieldProvenance(
    origin: ReceiptFieldOrigin.assumed,
    explanation: text,
  );
  ReceiptFieldProvenance _owner(String text) => ReceiptFieldProvenance(
    origin: ReceiptFieldOrigin.ownerEdited,
    explanation: text,
  );
}
