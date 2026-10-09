import 'package:flutter/foundation.dart';
import '../../../core/adapters/i_reseebo_data_adapter.dart';

class ReceiptDetailController extends ChangeNotifier {
  ReceiptDetailController(this.adapter, this.receiptId);
  final IReseeboDataAdapter adapter;
  final String receiptId;
  ReceiptDetail? detail;
  final Map<String, Product> products = {};
  Object? error;
  bool loading = true;
  bool _disposed = false;
  int _request = 0;
  Future<void> load() async {
    final request = ++_request;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await adapter.getReceipt(receiptId);
      final referenced = <String, Product>{};
      for (final id in result.lines.map((line) => line.productId).toSet()) {
        final product = await adapter.getProductById(id);
        if (product != null) referenced[id] = product;
      }
      if (_disposed || request != _request) return;
      detail = result;
      products
        ..clear()
        ..addAll(referenced);
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
