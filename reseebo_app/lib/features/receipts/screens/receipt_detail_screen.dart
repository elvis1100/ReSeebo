import 'package:flutter/material.dart';
import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../comparison/screens/product_comparison_screen.dart';
import '../../receipt_scan/widgets/receipt_image_viewer.dart';
import '../state/receipt_detail_controller.dart';
import '../widgets/receipt_purchase_card.dart';

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
        appBar: AppBar(title: const Text('Saved receipt')),
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
                  Text(
                    detail.receipt.supplier.label,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    purchaseDate(
                      detail.receipt.purchasedAt,
                      withTime: detail.receipt.hasPurchaseTime,
                    ),
                  ),
                  if (detail.receipt.receiptNumber.isNotEmpty)
                    Text('Receipt no. ${detail.receipt.receiptNumber}'),
                  const SizedBox(height: AppSpacing.lg),
                  ReceiptImagesPreview(paths: detail.receipt.imagePaths),
                  const SizedBox(height: AppSpacing.lg),
                  for (final line in detail.lines)
                    ReceiptPurchaseCard(
                      line: line,
                      product: controller.products[line.productId],
                      onCompare: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProductComparisonScreen(
                            adapter: widget.adapter,
                            productId: line.productId,
                          ),
                        ),
                      ),
                    ),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.sm,
                    children: [
                      const Text('Recorded purchase total'),
                      CurrencyText(
                        cents: detail.receipt.totalCents,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  if (detail.receipt.notes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.lg),
                      child: Text('Notes: ${detail.receipt.notes}'),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Saved on ${purchaseDate(detail.receipt.createdAt, withTime: true)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
      );
    },
  );
}
