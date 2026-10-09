import 'package:flutter/material.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/constants/formatters.dart';
import '../../receipts/screens/receipt_detail_screen.dart';

class DuplicateReviewDialog extends StatefulWidget {
  const DuplicateReviewDialog({
    super.key,
    required this.adapter,
    required this.receiptIds,
  });
  final IReseeboDataAdapter adapter;
  final List<String> receiptIds;
  @override
  State<DuplicateReviewDialog> createState() => _DuplicateReviewDialogState();
}

class _DuplicateReviewDialogState extends State<DuplicateReviewDialog> {
  final Map<String, Receipt> _receipts = {};
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
        /* The source route can retry loading each candidate. */
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
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(receipt?.supplier.label ?? 'Earlier saved receipt'),
              subtitle: receipt == null
                  ? null
                  : Text(
                      '${purchaseDate(receipt.purchasedAt, withTime: receipt.hasPurchaseTime)} · ${pesos(receipt.totalCents)}',
                    ),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => Navigator.push(
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
