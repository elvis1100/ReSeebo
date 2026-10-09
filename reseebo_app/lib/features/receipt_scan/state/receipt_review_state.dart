import 'package:flutter/foundation.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/services/exact_product_match.dart';
import '../../../core/services/receipt_purchase_datetime.dart';
import '../../../core/services/receipt_layout.dart';

enum ReceiptLineField {
  description('Description'),
  quantity('Quantity'),
  piecesPerPack('Pieces per pack'),
  amount('Amount paid');

  const ReceiptLineField(this.label);
  final String label;
}

class ReceiptReviewState extends ChangeNotifier {
  ReceiptReviewState({required this.adapter, required ReceiptDraft draft})
    : draft = draft.snapshot() {
    for (final line in this.draft.lines) {
      _prepareLine(line);
    }
  }

  /// New reviews use the final amount paid. Retain the net amount from older
  /// drafts without exposing a second deduction; saved history is untouched.
  void _prepareLine(ParsedLineItem line) {
    if (line.discountCents != 0) {
      line.grossAmountCents = line.netAmountCents;
      line.discountCents = 0;
    }
    if (line.unit == null) {
      line.unit = PurchaseUnit.piece;
      line.piecesPerPack = 1;
      line.confirmed = false;
    }
  }

  final IReseeboDataAdapter adapter;
  final ReceiptDraft draft;
  List<Product> products = [];
  List<Supplier> suppliers = [];
  bool loading = true;
  bool saving = false;
  String? error;
  int selectedPage = 0;

  List<ReceiptOcrPage> get pages => draft.ocrPages.isNotEmpty
      ? draft.ocrPages
      : draft.imagePaths.indexed
            .map(
              (entry) => ReceiptOcrPage(
                imagePath: entry.$2,
                recognitionImagePath: entry.$1 == 0
                    ? draft.recognitionImagePath
                    : null,
                textLines: draft.imagePaths.length == 1
                    ? draft.textLines
                    : const [],
              ),
            )
            .toList();

  void selectPage(int index) {
    if (saving || index < 0 || index >= pages.length) return;
    selectedPage = index;
    _changed();
  }

  void editText(ParsedLineItem line, ReceiptLineField field, String text) {
    if (saving) return;
    switch (field) {
      case ReceiptLineField.description:
        line.description = text;
        line.productId = null;
        line.matchOrigin = null;
      case ReceiptLineField.quantity:
        line.quantity = parseQuantity(text);
        line.quantityEdited = true;
      case ReceiptLineField.piecesPerPack:
        line.piecesPerPack = parseQuantity(text);
      case ReceiptLineField.amount:
        line.grossAmountCents = parsePesos(text);
        line.amountEdited = true;
    }
    changed(line: line, affectsTotal: field == ReceiptLineField.amount);
  }

  void setUnit(ParsedLineItem line, PurchaseUnit unit) {
    if (saving) return;
    final previous = line.unit;
    line.unit = unit;
    if (unit == PurchaseUnit.piece) {
      line.piecesPerPack = 1;
    } else if (previous != PurchaseUnit.pack) {
      line.piecesPerPack = null;
    }
    changed(line: line);
  }

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
      if (draft.supplierId == null) {
        final matches = suppliers
            .where(
              (supplier) =>
                  _key(supplier.name) == _key(draft.supplierName) &&
                  (draft.supplierBranch.isEmpty ||
                      _key(supplier.branch) == _key(draft.supplierBranch)),
            )
            .toList();
        if (matches.length == 1) draft.supplierId = matches.single.id;
      }
      for (final supplier in suppliers) {
        if (supplier.id == draft.supplierId) {
          draft.supplierName = supplier.name;
          draft.supplierBranch = supplier.branch;
          draft.supplierNotes = '';
          break;
        }
      }
      refreshDateSuggestion();
      // Only a unique mapping previously confirmed by the owner may prefill
      // product identity. Similar catalog names still need an explicit choice.
      final aliases = <String, List<ProductMatchSuggestion>>{};
      for (final line in draft.lines) {
        if (line.productId != null || line.description.trim().isEmpty) continue;
        final key = _key(line.description);
        final matches = aliases[key] ??= await adapter.matchAliases(
          line.description,
        );
        final exactIds = matches
            .where((match) => match.exactAlias)
            .map((match) => match.product.id)
            .where((id) => productFor(id) != null)
            .toSet();
        if (exactIds.length == 1) {
          line.productId = exactIds.single;
          line.matchOrigin = 'Previously matched';
          line.confirmed = false;
        } else if (exactIds.isEmpty) {
          final product = exactProductMatch(line.description, products);
          if (product != null) {
            line.productId = product.id;
            line.matchOrigin = 'Matched from receipt';
            line.confirmed = false;
          }
        }
      }
    } catch (failure) {
      error = userMessage(failure);
    } finally {
      loading = false;
      _changed();
    }
  }

  /// Re-evaluate only OCR-derived dates. An owner edit always wins over reload
  /// or a changed supplier preference; no saved purchase is modified here.
  void refreshDateSuggestion() {
    if (draft.dateManuallyEdited || draft.dateConfirmed) return;
    final source = pages
        .expand(
          (page) => [...recognizedReceiptText(page.textLines).split('\n'), ''],
        )
        .toList();
    if (source.every((row) => row.trim().isEmpty)) return;
    final supplier = suppliers
        .where((value) => value.id == draft.supplierId)
        .firstOrNull;
    final suggestion = ReceiptPurchaseDateTime().suggest(
      source,
      dateOrder: supplier?.dateOrder,
    );
    draft.purchasedAt = suggestion.purchasedAt;
    draft.hasPurchaseTime = suggestion.hasPurchaseTime;
    draft.dateFromReceipt = suggestion.purchasedAt != null;
    draft.dateCandidates = suggestion.candidates;
  }

  Future<void> chooseDateCandidate(
    PurchaseDateCandidate candidate, {
    bool remember = false,
  }) async {
    if (saving || loading || !draft.dateCandidates.contains(candidate)) return;
    final supplierId = draft.supplierId;
    if (remember) {
      final supplier = suppliers
          .where((value) => value.id == supplierId)
          .firstOrNull;
      if (supplier == null) {
        throw const ValidationException('Select a saved supplier first.');
      }
      await adapter.saveSupplier(
        Supplier(
          id: supplier.id,
          name: supplier.name,
          branch: supplier.branch,
          notes: supplier.notes,
          dateOrder: candidate.order,
        ),
      );
    }
    if (_disposed || draft.supplierId != supplierId || draft.dateManuallyEdited) {
      return;
    }
    draft.purchasedAt = candidate.date;
    draft.hasPurchaseTime = candidate.hasTime;
    draft.dateFromReceipt = true;
    draft.dateManuallyEdited = true;
    draft.dateConfirmed = false;
    changed();
  }

  static String _key(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Product? productFor(String? id) {
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }

  void changed({ParsedLineItem? line, bool affectsTotal = false}) {
    if (line != null) line.confirmed = false;
    if (affectsTotal) draft.totalDifferenceConfirmed = false;
    draft.allowDuplicate = false;
    _changed();
  }

  void addLine() {
    draft.lines.add(ParsedLineItem(unit: PurchaseUnit.piece, piecesPerPack: 1));
    draft.totalDifferenceConfirmed = false;
    draft.allowDuplicate = false;
    _changed();
  }

  void removeLine(ParsedLineItem line) {
    draft.lines.remove(line);
    draft.allowDuplicate = false;
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
    if (saving || lineProblem(line, requireConfirmation: false) != null) return;
    line.confirmed = true;
    _changed();
  }

  String? lineProblem(ParsedLineItem line, {bool requireConfirmation = true}) {
    if (line.possibleDuplicateOf != null) {
      return 'Resolve the possible overlap with the previous photo.';
    }
    if (line.description.trim().isEmpty) {
      return 'Enter the product name.';
    }
    if (line.productId != null && productFor(line.productId) == null) {
      return 'This product is no longer available. Choose another product.';
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
      return 'Enter the total amount paid for this item.';
    }
    if (line.discountCents < 0 ||
        line.discountCents >= line.grossAmountCents!) {
      return 'Check the amount paid for this item.';
    }
    if (requireConfirmation && !line.confirmed) {
      return 'Check and confirm this product, quantity, and amount.';
    }
    return null;
  }

  int get confirmedCount => draft.lines.where((line) => line.confirmed).length;

  int? get lineTotalCents {
    var sum = 0;
    for (final line in draft.lines) {
      final gross = line.grossAmountCents;
      if (gross == null ||
          gross <= 0 ||
          gross > maxAmountCents ||
          line.discountCents < 0 ||
          line.discountCents >= gross) {
        return null;
      }
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
