import 'package:flutter/foundation.dart';
import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/constants/formatters.dart';

class BasketController extends ChangeNotifier {
  BasketController(this.adapter);
  final IReseeboDataAdapter adapter;
  List<Product> products = [];
  List<Supplier> suppliers = [];
  bool loading = true;
  Object? error;
  bool calculating = false;
  String? calculationError;
  final Set<String> invalidQuantityIds = {};
  final Set<String> invalidExtraSupplierIds = {};
  final Map<String, String> quantities = {};
  final Map<String, String> extraInputs = {};
  BasketEstimate? estimate;
  int _loadRequest = 0;
  int _calculationRequest = 0;
  bool _disposed = false;

  Future<void> load() async {
    final request = ++_loadRequest;
    _calculationRequest++;
    calculating = false;
    estimate = null;
    calculationError = null;
    invalidQuantityIds.clear();
    invalidExtraSupplierIds.clear();
    loading = true;
    error = null;
    notifyListeners();
    try {
      final savedProducts = await adapter.getProducts();
      final savedSuppliers = await adapter.getSuppliers();
      if (_disposed || request != _loadRequest) return;
      products = savedProducts;
      suppliers = savedSuppliers;
      quantities.removeWhere(
        (id, _) => !products.any((product) => product.id == id),
      );
      extraInputs.removeWhere(
        (id, _) => !suppliers.any((supplier) => supplier.id == id),
      );
    } catch (failure) {
      if (_disposed || request != _loadRequest) return;
      error = failure;
    } finally {
      if (!_disposed && request == _loadRequest) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void changeQuantity(String productId, String value) {
    if (calculating) return;
    quantities[productId] = value;
    _invalidate();
  }

  void changeExtra(String supplierId, String value) {
    if (calculating) return;
    extraInputs[supplierId] = value;
    _invalidate();
  }

  void _invalidate() {
    _calculationRequest++;
    estimate = null;
    calculating = false;
    calculationError = null;
    invalidQuantityIds.clear();
    invalidExtraSupplierIds.clear();
    notifyListeners();
  }

  List<Product> get selectedProducts =>
      products.where((product) => quantities.containsKey(product.id)).toList();
  List<Product> get availableProducts =>
      products.where((product) => !quantities.containsKey(product.id)).toList();

  void addProduct(Product product) {
    if (calculating || quantities.containsKey(product.id)) return;
    quantities[product.id] = '';
    _invalidate();
  }

  void removeProduct(String productId) {
    if (calculating) return;
    quantities.remove(productId);
    _invalidate();
  }

  void reset() {
    if (calculating) return;
    quantities.clear();
    extraInputs.clear();
    _invalidate();
  }

  String? quantityError(String productId) {
    if (parseQuantity(quantities[productId] ?? '') != null) return null;
    final name =
        products
            .where((product) => product.id == productId)
            .firstOrNull
            ?.name ??
        'Product $productId';
    return '$name: enter a whole quantity from 1 to $maxQuantity pieces.';
  }

  String? extraError(String supplierId) {
    final input = extraInputs[supplierId] ?? '';
    if (input.trim().isEmpty || parsePesos(input) != null) return null;
    final name =
        suppliers
            .where((supplier) => supplier.id == supplierId)
            .firstOrNull
            ?.label ??
        'Supplier $supplierId';
    return '$name: enter a valid peso amount with at most two decimals.';
  }

  /// Inputs are frozen until this request finishes. Edits invalidate the prior
  /// estimate; a reload or disposal also prevents a late result from applying.
  Future<bool> calculate() async {
    if (calculating || _disposed) return false;
    invalidQuantityIds.clear();
    invalidExtraSupplierIds.clear();
    calculationError = null;
    final targets = <String, int>{};
    for (final entry in quantities.entries) {
      final target = parseQuantity(entry.value);
      if (target == null) {
        invalidQuantityIds.add(entry.key);
        continue;
      }
      targets[entry.key] = target;
    }
    final extras = <String, int>{};
    for (final entry in extraInputs.entries) {
      final amount = entry.value.trim().isEmpty ? 0 : parsePesos(entry.value);
      if (amount == null) {
        invalidExtraSupplierIds.add(entry.key);
        continue;
      }
      extras[entry.key] = amount;
    }
    if (invalidQuantityIds.isNotEmpty || invalidExtraSupplierIds.isNotEmpty) {
      notifyListeners();
      return false;
    }
    if (targets.isEmpty) {
      calculationError = 'Add a product and enter its restock quantity.';
      notifyListeners();
      return false;
    }
    final request = ++_calculationRequest;
    calculating = true;
    estimate = null;
    calculationError = null;
    notifyListeners();
    try {
      final result = await adapter.calculateBasket(
        targets,
        additionalCostsCents: extras,
      );
      if (_disposed || request != _calculationRequest) return false;
      estimate = result;
      return true;
    } catch (failure) {
      if (_disposed || request != _calculationRequest) return false;
      calculationError = userMessage(failure);
      return false;
    } finally {
      if (!_disposed && request == _calculationRequest) {
        calculating = false;
        notifyListeners();
      }
    }
  }

  int get totalAdditionalCostsCents =>
      estimate?.groups.fold<int>(
        0,
        (sum, group) => sum + group.additionalCostCents,
      ) ??
      0;

  BasketSupplierAlternative? get bestCompleteAlternative {
    final complete =
        estimate?.alternatives
            .where((alternative) => alternative.missingProducts.isEmpty)
            .toList() ??
        <BasketSupplierAlternative>[];
    complete.sort((a, b) => a.knownTotalCents.compareTo(b.knownTotalCents));
    return complete.isEmpty ? null : complete.first;
  }

  int? get completeAlternativeSavings {
    if (estimate == null ||
        estimate!.missingProducts.isNotEmpty ||
        bestCompleteAlternative == null) {
      return null;
    }
    return estimate!.totalCents - bestCompleteAlternative!.knownTotalCents;
  }

  @override
  void dispose() {
    _disposed = true;
    _loadRequest++;
    _calculationRequest++;
    super.dispose();
  }
}
