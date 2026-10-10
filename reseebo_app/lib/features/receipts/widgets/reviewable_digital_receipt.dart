import 'package:flutter/material.dart';

import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/widgets/receipt_paper.dart';
import '../../receipt_scan/widgets/receipt_suggestion_label.dart';
import 'receipt_images_preview.dart';

/// Nullable evidence remains readable without substituting zero amounts or
/// confirming assumptions. Historical snapshots use this read-only renderer.
class ReviewableDigitalReceipt extends StatelessWidget {
  const ReviewableDigitalReceipt({
    super.key,
    required this.draft,
    this.provisional = true,
  });
  final ReceiptDraft draft;
  final bool provisional;

  @override
  Widget build(BuildContext context) => ReceiptPaper(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          draft.supplierName.trim().isEmpty
              ? 'Unknown supplier'
              : draft.supplierName,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (draft.supplierBranch.trim().isNotEmpty) Text(draft.supplierBranch),
        const SizedBox(height: 8),
        Text(
          draft.purchasedAt == null
              ? 'Purchase date not available'
              : 'Purchase date: ${purchaseDate(draft.purchasedAt!, withTime: draft.hasPurchaseTime)}',
        ),
        ReceiptSuggestionLabel(
          provenance: draft.provenance[ReceiptMetadataField.purchasedAt],
        ),
        if (draft.receiptNumber.isNotEmpty)
          Text('Receipt no. ${draft.receiptNumber}'),
        const Divider(height: 24),
        if (draft.lines.isEmpty) const Text('No items found yet'),
        for (final line in draft.lines) ...[
          Text(
            line.description.isEmpty
                ? 'Item name not available'
                : line.description,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            line.quantity == null
                ? 'Quantity not available'
                : '${line.quantity} ${line.unit == PurchaseUnit.pack
                      ? 'packs'
                      : line.unit == PurchaseUnit.piece
                      ? 'pieces'
                      : 'units to check'}',
          ),
          if (line.unit == PurchaseUnit.pack)
            Text(
              line.piecesPerPack == null
                  ? 'Pack contents not available'
                  : '${line.piecesPerPack} pieces per pack',
            ),
          Text(
            line.netAmountCents == null
                ? 'Amount not available'
                : pesos(line.netAmountCents!),
          ),
          ReceiptSuggestionLabel(
            provenance: line.provenance[ReceiptSuggestionField.amount],
          ),
          if (provisional && line.costPerPieceCents != null)
            Text(
              'Provisional cost per piece: ${pesos(line.costPerPieceCents!)}',
            ),
          const Divider(height: 24),
        ],
        Text(
          provisional ? 'Provisional total' : 'Prior total',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          draft.detectedTotalCents == null
              ? 'Total not available'
              : pesos(draft.detectedTotalCents!),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (draft.totalIsPartial)
          const Text('Partial total; some amounts need review.'),
        ReceiptSuggestionLabel(
          provenance: draft.provenance[ReceiptMetadataField.total],
        ),
        if (draft.notes.isNotEmpty) Text('Notes: ${draft.notes}'),
        const Divider(height: 24),
        ReceiptImagesPreview(paths: draft.imagePaths),
        if (draft.rawText.isNotEmpty)
          Material(
            color: Colors.transparent,
            child: ExpansionTile(
              title: const Text('Original extracted text'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(draft.rawText),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
