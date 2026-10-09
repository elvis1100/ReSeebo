import 'package:flutter/material.dart';
import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../comparison/screens/product_comparison_screen.dart';
import '../state/receipt_detail_controller.dart';
import '../widgets/saved_digital_receipt.dart';

class ReceiptDetailScreen extends StatefulWidget {
  const ReceiptDetailScreen({
    super.key,
    required this.adapter,
    required this.receiptId,
    this.justSaved = false,
  });
  final IReseeboDataAdapter adapter;
  final String receiptId;
  final bool justSaved;
  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  late final controller = ReceiptDetailController(
    widget.adapter,
    widget.receiptId,
  );
  @override
  void initState() {
    super.initState();
    controller.load();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final detail = controller.detail;
      return Scaffold(
        appBar: AppBar(title: const Text('Receipt details')),
        body: controller.loading
            ? const Center(child: CircularProgressIndicator())
            : controller.error != null
            ? SingleChildScrollView(
                child: ErrorState(
                  message: userMessage(controller.error!),
                  onRetry: controller.load,
                ),
              )
            : detail == null
            ? const SizedBox.shrink()
            : ListView(
                padding: AppSpacing.page,
                children: [
                  if (widget.justSaved) ...[
                    const Notice(
                      message:
                          'Purchase saved on this device. Compare each product’s recorded prices below.',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  SavedDigitalReceipt(
                    detail: detail,
                    products: controller.products,
                    onCompare: (line) => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProductComparisonScreen(
                          dataAdapter: widget.adapter,
                          productId: line.productId,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      );
    },
  );
}
