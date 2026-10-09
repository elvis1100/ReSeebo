import 'package:flutter/foundation.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/constants/formatters.dart';

enum ReceiptLineField {
  description('Description'),
  quantity('Qty'),
  piecesPerPack('Pcs/pack'),
  amount('Line amount'),
  discount('Discount');

  const ReceiptLineField(this.label);
  final String label;
}

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
  int selectedPage = 0;
  String? targetLineId;
  ReceiptLineField? targetField;
  final Set<int> selectedTokens = {};

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

  List<OcrTextToken> get pageTokens => pages.isEmpty
      ? const []
      : pages[selectedPage].textLines.expand((line) => line.tokens).toList();
  String get selectedText => _selectedText();

  String _selectedText() {
    final tokens = pageTokens;
    final indices = selectedTokens.toList()..sort();
    return indices
        .where((i) => i < tokens.length)
        .map((i) => tokens[i].text)
        .join(' ');
  }

  void selectPage(int index) {
    if (saving || index < 0 || index >= pages.length) return;
    selectedPage = index;
    selectedTokens.clear();
    _changed();
  }

  void selectTarget(String lineId, ReceiptLineField field) {
    if (saving) return;
    final line = draft.lines.where((line) => line.id == lineId).firstOrNull;
    if (line == null) return;
    targetLineId = lineId;
    targetField = field;
    if (line.sourcePage >= 0 && line.sourcePage < pages.length) {
      selectedPage = line.sourcePage;
    }
    selectedTokens.clear();
    _changed();
  }

  void toggleToken(int index) {
    if (saving ||
        targetField == null ||
        index < 0 ||
        index >= pageTokens.length) {
      return;
    }
    if (!selectedTokens.remove(index)) selectedTokens.add(index);
    _changed();
  }

  /// OCR assignment accepts only an unambiguous value. Rejection does not
  /// alter existing data or confirmation; no OCR character substitutions apply.
  String? assignText(String text) {
    if (saving) return 'Wait for the receipt to finish saving.';
    final line = draft.lines
        .where((line) => line.id == targetLineId)
        .firstOrNull;
    final field = targetField;
    if (line == null || field == null) return 'Choose a field first.';
    final value = text.trim();
    if (field == ReceiptLineField.description) {
      if (value.isEmpty) return 'Select the receipt description.';
      line.description = value;
      line.productId = null;
    } else if (field == ReceiptLineField.quantity ||
        field == ReceiptLineField.piecesPerPack) {
      final quantity = parseQuantity(value);
      if (quantity == null) {
        return 'Select one whole number greater than zero, or type it manually.';
      }
      if (field == ReceiptLineField.quantity) {
        line.quantity = quantity;
      } else {
        if (line.unit != PurchaseUnit.pack) {
          return 'Choose packs before assigning pack contents.';
        }
        line.piecesPerPack = quantity;
      }
    } else {
      final amount = parsePesos(value);
      if (amount == null || (field == ReceiptLineField.amount && amount <= 0)) {
        return 'Select one peso amount, or type it manually.';
      }
      if (field == ReceiptLineField.amount) {
        line.grossAmountCents = amount;
      } else {
        if (line.grossAmountCents == null || amount >= line.grossAmountCents!) {
          return 'Discount must be less than the line amount.';
        }
        line.discountCents = amount;
      }
    }
    changed(
      line: line,
      affectsTotal:
          field == ReceiptLineField.amount ||
          field == ReceiptLineField.discount,
    );
    selectedTokens.clear();
    return null;
  }

  void editText(ParsedLineItem line, ReceiptLineField field, String text) {
    if (saving) return;
    switch (field) {
      case ReceiptLineField.description:
        line.description = text;
        line.productId = null;
      case ReceiptLineField.quantity:
        line.quantity = parseQuantity(text);
      case ReceiptLineField.piecesPerPack:
        line.piecesPerPack = parseQuantity(text);
      case ReceiptLineField.amount:
        line.grossAmountCents = parsePesos(text);
      case ReceiptLineField.discount:
        // Invalid discounts remain invalid at the service boundary.
        line.discountCents = parsePesos(text) ?? -1;
    }
    changed(
      line: line,
      affectsTotal:
          field == ReceiptLineField.amount ||
          field == ReceiptLineField.discount,
    );
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
    draft.allowDuplicate = false;
    _changed();
  }

  void addLine() {
    draft.lines.add(ParsedLineItem());
    draft.totalDifferenceConfirmed = false;
    draft.allowDuplicate = false;
    _changed();
  }

  void removeLine(ParsedLineItem line) {
    draft.lines.remove(line);
    draft.allowDuplicate = false;
    if (targetLineId == line.id) {
      targetLineId = null;
      targetField = null;
      selectedTokens.clear();
    }
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
