import 'package:flutter/material.dart';
import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../comparison/screens/product_comparison_screen.dart';
import '../state/receipt_detail_controller.dart';
import '../state/pending_receipt_controller.dart';
import '../widgets/receipt_revision_history.dart';
import '../widgets/saved_digital_receipt.dart';
import 'pending_receipt_review_route.dart';
import 'pending_receipt_screen.dart';

class ReceiptDetailScreen extends StatefulWidget {
  const ReceiptDetailScreen({
    super.key,
    required this.adapter,
    required this.receiptId,
    this.justSaved = false,
    this.onPendingReceiptSaved,
    this.onOpenPendingReceipt,
    this.onReceiptChanged,
  });
  final IReseeboDataAdapter adapter;
  final String receiptId;
  final bool justSaved;
  final ValueChanged<PendingSaveResult>? onPendingReceiptSaved;

  /// Prefer this awaited route hook when a parent owns navigation. Returning
  /// reloads the confirmed detail after a correction, including its history.
  /// The legacy void saved callback remains supported for older callers.
  final Future<void> Function(String pendingId)? onOpenPendingReceipt;
  final VoidCallback? onReceiptChanged;
  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  bool _editing = false;
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

  Future<void> _openPending(String id) async {
    final route = widget.onOpenPendingReceipt;
    if (route != null) {
      await route(id);
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              PendingReceiptScreen(adapter: widget.adapter, pendingId: id),
        ),
      );
    }
    if (!mounted) return;
    await controller.load();
    if (mounted) widget.onReceiptChanged?.call();
  }

  Future<void> _edit() async {
    if (_editing || controller.loading) return;
    setState(() => _editing = true);
    final editor = PendingReceiptController(widget.adapter);
    try {
      final active = await widget.adapter.getPendingCorrection(
        widget.receiptId,
      );
      if (active != null) {
        await editor.load(active.id);
        if (editor.error != null) throw editor.error!;
      } else {
        final edit = await widget.adapter.getConfirmedReceiptEdit(
          widget.receiptId,
        );
        editor.beginCorrection(edit, importedAt: DateTime.now());
      }
      if (!mounted) return;
      final outcome = await openPendingReceiptReview(
        context,
        controller: editor,
        onOpenPendingReceipt: _openPending,
      );
      if (!mounted) return;
      if (outcome?.saved case final result?) {
        widget.onPendingReceiptSaved?.call(result);
        if (widget.onOpenPendingReceipt != null ||
            widget.onPendingReceiptSaved == null) {
          await _openPending(result.id);
        }
      } else if (outcome?.confirmed != null || outcome?.reload == true) {
        await controller.load();
        if (mounted) widget.onReceiptChanged?.call();
      }
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(failure))));
      }
    } finally {
      editor.dispose();
      if (mounted) setState(() => _editing = false);
    }
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
                  AppButton(
                    label: 'Edit receipt',
                    variant: ButtonVariant.outlined,
                    isFullWidth: true,
                    isLoading: _editing,
                    onPressed: _editing ? null : _edit,
                  ),
                  const SizedBox(height: 16),
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
                  if (controller.revisions.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    ReceiptRevisionHistory(revisions: controller.revisions),
                  ],
                  if (controller.historyError != null) ...[
                    const SizedBox(height: 16),
                    Notice(
                      warning: true,
                      message:
                          'Could not load correction history. Your saved purchase is still available.',
                    ),
                    TextButton(
                      onPressed: controller.load,
                      child: const Text('Retry history'),
                    ),
                  ],
                ],
              ),
      );
    },
  );
}
