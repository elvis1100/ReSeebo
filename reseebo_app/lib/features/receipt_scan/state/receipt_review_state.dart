import 'package:flutter/foundation.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';

class ReceiptReviewState extends ChangeNotifier {
  ReceiptReviewState({required this.adapter, required ReceiptDraft draft})
    : draft = draft.snapshot();
  final IReseeboDataAdapter adapter;
  final ReceiptDraft draft;
  List<Product> products = [];
  List<Supplier> suppliers = [];
  bool loading = true;
  bool saving = false;
  String? error;
  bool _disposed = false;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    _changed();
    try {
      products = await adapter.getProducts();
      suppliers = await adapter.getSuppliers();
      for (final supplier in suppliers) {
        if (supplier.id == draft.supplierId) {
          draft.supplierName = supplier.name;
          draft.supplierBranch = supplier.branch;
          draft.supplierNotes = '';
          break;
        }
      }
    } catch (failure) {
      error = userMessage(failure);
    } finally {
      loading = false;
      _changed();
    }
  }

  Product? productFor(String? id) {
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }

  void changed({ParsedLineItem? line, bool affectsTotal = false}) {
    if (line != null) line.confirmed = false;
    if (affectsTotal) draft.totalDifferenceConfirmed = false;
    _changed();
  }

  void addLine() {
    draft.lines.add(ParsedLineItem());
    draft.totalDifferenceConfirmed = false;
    _changed();
  }

  void removeLine(ParsedLineItem line) {
    draft.lines.remove(line);
    for (final remaining in draft.lines) {
      if (remaining.possibleDuplicateOf == line.id) {
        remaining.possibleDuplicateOf = null;
        remaining.confirmed = false;
      }
    }
    draft.totalDifferenceConfirmed = false;
    _changed();
  }

  void confirmLine(ParsedLineItem line) {
    line.confirmed = true;
    _changed();
  }

  String? lineProblem(ParsedLineItem line, {bool requireConfirmation = true}) {
    if (line.possibleDuplicateOf != null) {
      return 'Resolve the possible overlap with the previous photo.';
    }
    if (line.description.trim().isEmpty) {
      return 'Enter the receipt description.';
    }
    if (productFor(line.productId) == null) {
      return 'Choose the exact product, brand, variant, and size.';
    }
    if (line.quantity == null ||
        line.quantity! <= 0 ||
        line.quantity! > maxQuantity) {
      return 'Enter a valid whole purchase quantity.';
    }
    if (line.unit == null) return 'Choose pieces or packs.';
    if (line.unit == PurchaseUnit.piece &&
        line.piecesPerPack != null &&
        line.piecesPerPack != 1) {
      return 'Individual pieces must use one piece per unit. Choose pieces again.';
    }
    if (line.unit == PurchaseUnit.pack &&
        (line.piecesPerPack == null ||
            line.piecesPerPack! <= 0 ||
            line.piecesPerPack! > maxQuantity)) {
      return 'Enter the confirmed pieces per pack.';
    }
    if (line.grossAmountCents == null ||
        line.grossAmountCents! <= 0 ||
        line.grossAmountCents! > maxAmountCents) {
      return 'Enter the total line amount before discount.';
    }
    if (line.discountCents < 0 ||
        line.discountCents >= line.grossAmountCents!) {
      return 'Discount must be zero or less than the line amount.';
    }
    if (requireConfirmation && !line.confirmed) {
      return 'Check and confirm this product, quantity, and amount.';
    }
    return null;
  }

  int? get lineTotalCents {
    var sum = 0;
    for (final line in draft.lines) {
      if (line.netAmountCents == null || line.netAmountCents! <= 0) return null;
      sum += line.netAmountCents!;
    }
    return sum;
  }

  bool get hasTotalDifference =>
      draft.detectedTotalCents != null &&
      lineTotalCents != null &&
      draft.detectedTotalCents != lineTotalCents;

  String? get problem {
    if (draft.supplierName.trim().isEmpty) {
      return 'Enter or choose the supplier.';
    }
    if (draft.purchasedAt == null || !draft.dateConfirmed) {
      return 'Choose and confirm the purchase date.';
    }
    if (draft.lines.isEmpty) return 'Add at least one purchase line.';
    if (draft.lines.length > 1000) {
      return 'Save no more than 1,000 items on one receipt.';
    }
    for (var index = 0; index < draft.lines.length; index++) {
      final issue = lineProblem(draft.lines[index]);
      if (issue != null) return 'Line ${index + 1}: $issue';
    }
    if ((lineTotalCents ?? 0) > maxAmountCents) {
      return 'This purchase total exceeds the supported amount.';
    }
    if (hasTotalDifference && !draft.totalDifferenceConfirmed) {
      return 'Review and acknowledge the difference from the detected receipt total.';
    }
    return null;
  }

  Future<SaveReceiptResult> save() async {
    if (saving) {
      throw const ValidationException('This receipt is already being saved.');
    }
    final issue = problem;
    if (issue != null) throw ValidationException(issue);
    saving = true;
    error = null;
    _changed();
    try {
      return await adapter.saveConfirmedReceipt(draft);
    } finally {
      saving = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
