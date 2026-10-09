import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/adapters/i_reseebo_data_adapter.dart';

enum DashboardTab { receipts, products }

class DashboardController extends ChangeNotifier {
  DashboardController(this.adapter);
  final IReseeboDataAdapter adapter;
  StoreProfile profile = const StoreProfile();
  List<Receipt> receipts = [];
  List<Product> products = [];
  Map<String, double> latestCosts = {};
  Map<String, DateTime> latestCostDates = {};
  DashboardTab tab = DashboardTab.receipts;
  bool loading = true;
  Object? error;
  String query = '';
  Timer? _debounce;
  int _request = 0;
  bool _disposed = false;

  void search(String value) {
    query = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), load);
  }

  void selectTab(DashboardTab value) {
    if (tab == value) return;
    tab = value;
    _debounce?.cancel();
    load();
  }

  Future<void> load() async {
    final request = ++_request;
    final selectedTab = tab;
    final searchQuery = query;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final savedProfile = await adapter.getStoreProfile();
      if (selectedTab == DashboardTab.receipts) {
        final savedReceipts = await adapter.getRecentReceipts(
          query: searchQuery,
        );
        if (_disposed || request != _request) return;
        profile = savedProfile;
        receipts = savedReceipts;
      } else {
        final savedProducts = await adapter.getProducts(query: searchQuery);
        final costs = await adapter.getLatestProductCosts(
          savedProducts.map((product) => product.id),
        );
        if (_disposed || request != _request) return;
        profile = savedProfile;
        products = savedProducts;
        latestCosts = {};
        latestCostDates = {};
        for (final entry in costs.entries) {
          latestCosts[entry.key] = entry.value.costPerPieceCents;
          latestCostDates[entry.key] = entry.value.purchasedAt;
        }
      }
    } catch (failure) {
      if (_disposed || request != _request) return;
      error = failure;
    } finally {
      if (!_disposed && request == _request) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _debounce?.cancel();
    super.dispose();
  }
}
