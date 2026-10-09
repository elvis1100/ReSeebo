import '../errors/app_exception.dart';
import '../models/models.dart';
import 'pricing_service.dart';

class ReceiptValidator {
  /// Validate a private snapshot before any file or SQLite mutation. This also
  /// protects direct adapter callers that bypass the review screen's controls.
  static void validate(ReceiptDraft draft) {
    if (draft.operationId.trim().isEmpty) {
      throw const ValidationException(
        'A save operation identifier is required.',
      );
    }
    if (draft.supplierName.trim().isEmpty) {
      throw const ValidationException('Confirm the supplier name.');
    }
    if (draft.imagePath.trim().isEmpty) {
      throw const ValidationException(
        'Keep an original receipt image before saving.',
      );
    }
    if (draft.imagePaths.isEmpty ||
        draft.imagePaths.length > maxReceiptPages ||
        draft.imagePaths.first != draft.imagePath ||
        draft.imagePaths.any((path) => path.trim().isEmpty)) {
      throw const ValidationException(
        'Keep 1 to 20 ordered original receipt photos.',
      );
    }
    if (draft.purchasedAt == null || !draft.dateConfirmed) {
      throw const ValidationException('Confirm the purchase date.');
    }
    if (draft.lines.isEmpty) {
      throw const ValidationException('Add at least one purchased product.');
    }
    if (draft.lines.length > 1000) {
      throw const ValidationException(
        'Save no more than 1,000 items on one receipt.',
      );
    }
    var total = 0;
    for (var index = 0; index < draft.lines.length; index++) {
      final line = draft.lines[index];
      final prefix = 'Item ${index + 1}:';
      if (line.sourcePage < 0 || line.sourcePage >= draft.imagePaths.length) {
        throw ValidationException('$prefix select an existing receipt page.');
      }
      if (line.possibleDuplicateOf != null) {
        throw ValidationException(
          '$prefix review the possible overlap with the previous photo.',
        );
      }
      if (!line.confirmed || (line.productId ?? '').trim().isEmpty) {
        throw ValidationException('$prefix confirm an exact product match.');
      }
      if (line.description.trim().isEmpty) {
        throw ValidationException('$prefix enter the receipt description.');
      }
      if (line.quantity == null) {
        throw ValidationException('$prefix enter the purchased quantity.');
      }
      PricingService.validateQuantity(line.quantity!);
      if (line.unit == null) {
        throw ValidationException('$prefix choose pieces or packs.');
      }
      if (line.unit == PurchaseUnit.pack) {
        if (line.piecesPerPack == null) {
          throw ValidationException('$prefix confirm the pieces per pack.');
        }
        PricingService.validateQuantity(line.piecesPerPack!);
      } else {
        if (line.piecesPerPack != null && line.piecesPerPack != 1) {
          throw ValidationException(
            '$prefix individual pieces must use one piece per unit.',
          );
        }
        line.piecesPerPack = 1;
      }
      if (line.grossAmountCents == null) {
        throw ValidationException('$prefix enter the line amount.');
      }
      PricingService.validateMoney(line.grossAmountCents!, allowZero: false);
      if (line.discountCents < 0 ||
          line.discountCents >= line.grossAmountCents!) {
        throw ValidationException(
          '$prefix discount must be smaller than the line amount.',
        );
      }
      total += line.netAmountCents!;
      PricingService.validateMoney(total, allowZero: false);
    }
    if (draft.detectedTotalCents != null) {
      PricingService.validateMoney(draft.detectedTotalCents!);
      if (total != draft.detectedTotalCents &&
          !draft.totalDifferenceConfirmed) {
        throw const ValidationException(
          'The item amounts do not match the printed total. Review the amounts paid or confirm the difference before saving.',
        );
      }
    }
  }
}
