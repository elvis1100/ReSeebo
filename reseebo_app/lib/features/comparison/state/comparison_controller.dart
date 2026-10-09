import 'package:flutter/foundation.dart';
import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/services/pricing_service.dart';

class ComparisonController extends ChangeNotifier {
  ComparisonController(this.adapter, this.productId);
  final IReseeboDataAdapter adapter;
  final String productId;
  ProductComparisonData? data;
  Object? error;
  bool loading = true;
  String? selectedSupplierId;
  String? historySupplierId;
  String markupInput = '';
  String additionInput = '';
  String sellingInput = '';
  bool pesoAddition = false;
  bool includeExtraInProfit = false;
  String quantityInput = '';
  final Map<String, String> extraInputs = {};
  RestockEstimate? restock;
  String? restockError;
  bool calculating = false;
  String? baselineSupplierId;
  int _loadRequest = 0;
  int _restockRequest = 0;
  bool _disposed = false;

  Future<void> load({bool resetPricing = false}) async {
    final initializePricing = data == null || resetPricing;
    final request = ++_loadRequest;
    _restockRequest++;
    calculating = false;
    restock = null;
    restockError = null;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await adapter.getProductComparison(productId);
      if (_disposed || request != _loadRequest) return;
      data = result;
      if (!result.latestPrices.any(
        (row) => row.purchase.supplier.id == selectedSupplierId,
      )) {
        selectedSupplierId = result.latestPrices.isEmpty
            ? null
            : result.latestPrices.first.purchase.supplier.id;
      }
      if (initializePricing) {
        markupInput = result.effectiveMarkupPercent?.toString() ?? '';
        sellingInput = editablePesos(result.product.sellingPriceCents);
      }
      if (historySupplierId != null &&
          !result.latestPrices.any(
            (row) => row.purchase.supplier.id == historySupplierId,
          )) {
        historySupplierId = null;
      }
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

  PurchaseRecord? get selectedPurchase {
    for (final row in data?.latestPrices ?? <SupplierPriceRow>[]) {
      if (row.purchase.supplier.id == selectedSupplierId) return row.purchase;
    }
    return null;
  }

  List<PriceHistoryRecord> get filteredHistory => (data?.history ?? [])
      .where(
        (row) =>
            historySupplierId == null ||
            row.purchase.supplier.id == historySupplierId,
      )
      .toList();

  RestockSupplierEstimate? get selectedEstimate {
    for (final row in restock?.suppliers ?? <RestockSupplierEstimate>[]) {
      if (row.purchase.supplier.id == selectedSupplierId) return row;
    }
    return null;
  }

  double? get costUsedCents {
    final purchase = selectedPurchase;
    if (purchase == null) return null;
    final estimate = selectedEstimate;
    return purchase.costPerPieceCents +
        (includeExtraInProfit && estimate != null
            ? estimate.additionalCostCents / estimate.purchasedPieces
            : 0);
  }

  String? get pricingError {
    if (pesoAddition) {
      if (parsePesos(additionInput) == null) {
        return 'Enter a valid peso addition, including 0.00.';
      }
    } else if (parseMarkup(markupInput) == null) {
      return 'Choose a markup percentage, including 0%, to calculate a suggestion.';
    }
    if (sellingInput.trim().isNotEmpty && parsePesos(sellingInput) == null) {
      return 'Enter a selling price in pesos, with at most two decimal places.';
    }
    final cost = costUsedCents;
    if (cost != null) {
      try {
        if (pesoAddition) {
          PricingService.validateMoney(
            (cost + parsePesos(additionInput)!).round(),
          );
        } else {
          PricingService.suggestedSellingPriceCents(
            cost,
            parseMarkup(markupInput)!,
          );
        }
      } on AppException catch (failure) {
        return failure.message;
      }
    }
    return null;
  }

  int? get suggestedPriceCents {
    final cost = costUsedCents;
    if (cost == null || pricingError != null) return null;
    try {
      return pesoAddition
          ? (cost + parsePesos(additionInput)!).round()
          : PricingService.suggestedSellingPriceCents(
              cost,
              parseMarkup(markupInput)!,
            );
    } on AppException {
      return null;
    }
  }

  ProfitCalculation? get profit {
    final cost = costUsedCents;
    final selling = sellingInput.trim().isEmpty
        ? suggestedPriceCents
        : parsePesos(sellingInput);
    if (cost == null || selling == null) return null;
    try {
      return PricingService.profit(cost, selling);
    } on AppException {
      return null;
    }
  }

  void chooseSupplier(String id) {
    selectedSupplierId = id;
    notifyListeners();
  }

  void filterHistory(String? id) {
    historySupplierId = id;
    notifyListeners();
  }

  void changePricing({
    String? markup,
    String? addition,
    String? selling,
    bool? usePeso,
    bool? includeExtra,
  }) {
    if (markup != null) markupInput = markup;
    if (addition != null) additionInput = addition;
    if (selling != null) sellingInput = selling;
    if (usePeso != null) pesoAddition = usePeso;
    if (includeExtra != null) includeExtraInProfit = includeExtra;
    notifyListeners();
  }

  void changeRestock({String? quantity, String? supplierId, String? extra}) {
    if (quantity != null) quantityInput = quantity;
    if (supplierId != null && extra != null) extraInputs[supplierId] = extra;
    _restockRequest++;
    restock = null;
    calculating = false;
    restockError = null;
    notifyListeners();
  }

  Future<void> calculateRestock() async {
    if (calculating || _disposed) return;
    final target = parseQuantity(quantityInput);
    if (target == null) {
      restockError =
          'Enter a whole restock quantity from 1 to $maxQuantity pieces.';
      notifyListeners();
      return;
    }
    final extras = <String, int>{};
    for (final entry in extraInputs.entries) {
      final amount = entry.value.trim().isEmpty ? 0 : parsePesos(entry.value);
      if (amount == null) {
        restockError =
            'Enter valid travel/delivery costs in pesos, with at most two decimals.';
        notifyListeners();
        return;
      }
      extras[entry.key] = amount;
    }
    final request = ++_restockRequest;
    calculating = true;
    restockError = null;
    notifyListeners();
    try {
      final result = await adapter.calculateRestock(
        productId: productId,
        targetPieces: target,
        additionalCost: 0,
        additionalCostsCents: extras,
      );
      if (_disposed || request != _restockRequest) return;
      restock = result;
      final sorted = List<RestockSupplierEstimate>.of(result.suppliers)
        ..sort((a, b) => b.subtotalCents.compareTo(a.subtotalCents));
      if (!sorted.any(
        (row) => row.purchase.supplier.id == baselineSupplierId,
      )) {
        baselineSupplierId = sorted.isEmpty
            ? null
            : sorted.first.purchase.supplier.id;
      }
    } catch (failure) {
      if (_disposed || request != _restockRequest) return;
      restockError = userMessage(failure);
    } finally {
      if (!_disposed && request == _restockRequest) {
        calculating = false;
        notifyListeners();
      }
    }
  }

  void chooseBaseline(String id) {
    baselineSupplierId = id;
    notifyListeners();
  }

  RestockSupplierEstimate? get baseline {
    for (final row in restock?.suppliers ?? <RestockSupplierEstimate>[]) {
      if (row.purchase.supplier.id == baselineSupplierId) return row;
    }
    return null;
  }

  int productSavings(RestockSupplierEstimate row) =>
      (baseline?.subtotalCents ?? row.subtotalCents) - row.subtotalCents;
  int netSavings(RestockSupplierEstimate row) =>
      (baseline?.totalCents ?? row.totalCents) - row.totalCents;

  @override
  void dispose() {
    _disposed = true;
    _loadRequest++;
    _restockRequest++;
    super.dispose();
  }
}
