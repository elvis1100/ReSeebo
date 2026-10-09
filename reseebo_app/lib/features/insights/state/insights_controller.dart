import 'package:flutter/foundation.dart';
import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../models/store_insights.dart';
import '../services/store_insights_service.dart';

class InsightsController extends ChangeNotifier {
  InsightsController(IReseeboDataAdapter adapter)
    : _service = StoreInsightsService(adapter);
  final StoreInsightsService _service;
  List<ProductComparisonData> _data = [];
  InsightPeriod period = InsightPeriod.last30Days;
  bool loading = true;
  Object? error;
  bool _disposed = false;
  int _request = 0;
  StoreInsights get summary =>
      StoreInsightsService.summarize(_data, period, DateTime.now());

  void selectPeriod(InsightPeriod value) {
    period = value;
    notifyListeners();
  }

  Future<void> load() async {
    final request = ++_request;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await _service.load();
      if (!_disposed && request == _request) _data = result;
    } catch (failure) {
      if (!_disposed && request == _request) error = failure;
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
    super.dispose();
  }
}
