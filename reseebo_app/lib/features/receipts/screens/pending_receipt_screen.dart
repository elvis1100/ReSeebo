import 'package:flutter/material.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../state/pending_receipt_controller.dart';
import '../widgets/receipt_review_status.dart';
import '../widgets/reviewable_digital_receipt.dart';
import 'pending_receipt_review_route.dart';
import 'receipt_detail_screen.dart';

class PendingReceiptScreen extends StatefulWidget {
  const PendingReceiptScreen({
    super.key,
    required this.adapter,
    required this.pendingId,
    this.onConfirmed,
    this.onPendingSaved,
  });
  final IReseeboDataAdapter adapter;
  final String pendingId;

  /// Write notifications. This screen owns its review/confirmed routes, so
  /// callers may refresh their ledger without pushing a second detail route.
  final ValueChanged<SaveReceiptResult>? onConfirmed;
  final ValueChanged<PendingSaveResult>? onPendingSaved;

  @override
  State<PendingReceiptScreen> createState() => _PendingReceiptScreenState();
}

class _PendingReceiptScreenState extends State<PendingReceiptScreen> {
  late final controller = PendingReceiptController(widget.adapter);
  bool _opening = false;
  bool _showingConfirmed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await controller.load(widget.pendingId);
    if (mounted && controller.confirmedReceiptId != null) {
      _showConfirmed(controller.confirmedReceiptId!);
    }
  }

  void _showConfirmed(String id) {
    if (!mounted || _showingConfirmed) return;
    _showingConfirmed = true;
    Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(
        builder: (_) =>
            ReceiptDetailScreen(adapter: widget.adapter, receiptId: id),
      ),
    );
  }

  Future<void> _openOtherPending(String id) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PendingReceiptScreen(
          adapter: widget.adapter,
          pendingId: id,
          onConfirmed: widget.onConfirmed,
          onPendingSaved: widget.onPendingSaved,
        ),
      ),
    );
  }

  Future<void> _review() async {
    if (_opening || controller.loading || controller.saving) return;
    setState(() => _opening = true);
    final outcome = await openPendingReceiptReview(
      context,
      controller: controller,
      onOpenPendingReceipt: _openOtherPending,
    );
    if (!mounted) return;
    setState(() => _opening = false);
    if (outcome?.confirmed case final result?) {
      widget.onConfirmed?.call(result);
      _showConfirmed(result.receiptId);
    } else if (outcome?.saved case final result?) {
      widget.onPendingSaved?.call(result);
      await _load();
    } else if (outcome?.reload == true) {
      await _load();
    }
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
      final draft = controller.draft;
      final busy = controller.loading || controller.saving || _opening;
      return Scaffold(
        appBar: AppBar(title: const Text('Receipt details')),
        body: controller.loading
            ? const Center(child: CircularProgressIndicator())
            : draft == null
            ? controller.error == null
                  ? const SizedBox.shrink()
                  : SingleChildScrollView(
                      child: ErrorState(
                        message: userMessage(controller.error!),
                        onRetry: _load,
                      ),
                    )
            : ListView(
                padding: AppSpacing.page,
                children: [
                  const ReceiptReviewStatus(),
                  const SizedBox(height: 12),
                  Notice(
                    warning: true,
                    message: controller.correctionOfReceiptId == null
                        ? 'Suggested values are provisional. Review and confirm before they are used for prices or buying decisions.'
                        : 'This correction is Needs review. The last confirmed purchase stays active until you confirm the correction.',
                  ),
                  if (controller.error != null) ...[
                    const SizedBox(height: 12),
                    Notice(
                      warning: true,
                      message: userMessage(controller.error!),
                    ),
                    if (controller.error is RevisionConflictException)
                      TextButton(
                        onPressed: busy ? null : _load,
                        child: const Text('Reload current receipt'),
                      ),
                  ],
                  const SizedBox(height: 16),
                  ReviewableDigitalReceipt(draft: draft),
                ],
              ),
        bottomNavigationBar: draft == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: AppSpacing.page,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppButton(
                        label: 'Edit receipt',
                        variant: ButtonVariant.outlined,
                        isFullWidth: true,
                        onPressed: busy ? null : _review,
                      ),
                      const SizedBox(height: 8),
                      AppButton(
                        label: 'Review and confirm',
                        isFullWidth: true,
                        onPressed: busy ? null : _review,
                      ),
                    ],
                  ),
                ),
              ),
      );
    },
  );
}
