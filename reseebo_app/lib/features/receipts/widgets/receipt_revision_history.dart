import 'package:flutter/material.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/constants/formatters.dart';
import 'reviewable_digital_receipt.dart';

class ReceiptRevisionHistory extends StatelessWidget {
  const ReceiptRevisionHistory({super.key, required this.revisions});
  final List<ReceiptRevision> revisions;

  @override
  Widget build(BuildContext context) {
    if (revisions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Correction history',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        for (final revision in revisions)
          ExpansionTile(
            key: ValueKey('receipt-revision-${revision.revision}'),
            title: Text('Revision ${revision.revision}'),
            subtitle: Text(
              'Replaced on ${purchaseDate(revision.recordedAt.toLocal(), withTime: true)}',
            ),
            children: [
              ReviewableDigitalReceipt(
                draft: revision.draft,
                provisional: false,
              ),
            ],
          ),
      ],
    );
  }
}
