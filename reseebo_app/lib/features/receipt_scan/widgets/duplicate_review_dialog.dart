import 'package:flutter/material.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/constants/formatters.dart';
import '../../receipts/screens/receipt_detail_screen.dart';

class DuplicateReviewDialog extends StatefulWidget {
  const DuplicateReviewDialog({
    super.key,
    required this.adapter,
    required this.receiptIds,
    this.onOpenPendingReceipt,
  });
  final IReseeboDataAdapter adapter;
  final List<String> receiptIds;
  final ValueChanged<String>? onOpenPendingReceipt;
  @override
  State<DuplicateReviewDialog> createState() => _DuplicateReviewDialogState();
}

class _DuplicateReviewDialogState extends State<DuplicateReviewDialog> {
  final Map<String, Receipt> _receipts = {};
  final Map<String, PendingReceipt> _pending = {};
  final Set<String> _failed = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final id in widget.receiptIds) {
      try {
        final detail = await widget.adapter.getReceipt(id);
        if (mounted) setState(() => _receipts[id] = detail.receipt);
      } catch (_) {
        try {
          final pending = await widget.adapter.getPendingReceipt(id);
          if (mounted) setState(() => _pending[id] = pending);
        } catch (_) {
          if (mounted) setState(() => _failed.add(id));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Possible duplicate receipt'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Review the earlier receipt before saving again. Only continue if this is a separate purchase, including a second purchase on the same day.',
          ),
          const SizedBox(height: 12),
          ...widget.receiptIds.map((id) {
            final receipt = _receipts[id];
            final pending = _pending[id];
            final draft = pending?.draft;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                receipt?.supplier.label ??
                    (draft?.supplierName.trim().isNotEmpty == true
                        ? draft!.supplierName
                        : 'Earlier saved receipt'),
              ),
              subtitle: pending != null
                  ? Text(
                      'Needs review · ${draft!.purchasedAt == null ? 'Purchase date unresolved' : 'Estimated purchase date: ${purchaseDate(draft.purchasedAt!, withTime: draft.hasPurchaseTime)}'} · Provisional total: ${draft.detectedTotalCents == null ? 'Unresolved' : pesos(draft.detectedTotalCents!)}',
                    )
                  : receipt == null
                  ? Text(
                      _failed.contains(id)
                          ? 'Could not load this receipt. Keep reviewing and try again.'
                          : 'Loading earlier receipt…',
                    )
                  : Text(
                      '${purchaseDate(receipt.purchasedAt, withTime: receipt.hasPurchaseTime)} · ${pesos(receipt.totalCents)}',
                    ),
              trailing: const Icon(Icons.open_in_new),
              onTap: pending != null
                  ? widget.onOpenPendingReceipt == null
                        ? null
                        : () => widget.onOpenPendingReceipt!(id)
                  : receipt == null
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReceiptDetailScreen(
                          adapter: widget.adapter,
                          receiptId: id,
                        ),
                      ),
                    ),
            );
          }),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Keep reviewing'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('This is a separate purchase'),
      ),
    ],
  );
}
