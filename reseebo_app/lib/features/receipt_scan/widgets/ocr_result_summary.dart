import 'package:flutter/material.dart';

import '../../../core/constants/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../models/scan_result.dart';
import 'receipt_suggestion_label.dart';

String receiptTotalLabel(ReceiptDraft draft) => draft.totalIsPartial
    ? 'Partial estimated total'
    : !draft.provenance.containsKey(ReceiptMetadataField.total) &&
          draft.detectedTotalCents != null
    ? 'Recorded total'
    : draft.provenance[ReceiptMetadataField.total]?.origin ==
          ReceiptFieldOrigin.extracted
    ? 'Printed receipt total'
    : draft.lines.any(
        (line) =>
            line.provenance[ReceiptSuggestionField.amount]?.origin ==
            ReceiptFieldOrigin.history,
      )
    ? 'Estimated total'
    : 'Calculated total';

class OcrResultSummary extends StatelessWidget {
  const OcrResultSummary({
    super.key,
    required this.result,
    required this.draft,
  });
  final ScanResult result;
  final ReceiptDraft draft;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Needs review',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: AppColors.amberText),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${draft.lines.length} item${draft.lines.length == 1 ? '' : 's'} · ${(result.elapsedMs / 1000).toStringAsFixed(1)} seconds',
        ),
        Text(
          '${receiptTotalLabel(draft)}: ${draft.detectedTotalCents == null ? 'Unresolved' : pesos(draft.detectedTotalCents!)}',
        ),
        ReceiptSuggestionLabel(
          provenance: draft.provenance[ReceiptMetadataField.total],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Supplier: ${draft.supplierName.trim().isEmpty ? 'Unknown supplier' : draft.supplierName}',
        ),
        ReceiptSuggestionLabel(
          provenance: draft.provenance[ReceiptMetadataField.supplier],
        ),
        Text(
          'Purchase date: ${draft.purchasedAt == null ? 'Unresolved' : purchaseDate(draft.purchasedAt!, withTime: draft.hasPurchaseTime)}',
        ),
        ReceiptSuggestionLabel(
          provenance: draft.provenance[ReceiptMetadataField.purchasedAt],
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Suggestions stay outside confirmed purchase comparisons until you review and confirm.',
        ),
        for (final line in draft.lines) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            line.description,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (line.costPerPieceCents != null)
            Text(
              'Provisional cost per piece: ${pesos(line.costPerPieceCents!)}',
            )
          else
            const Text('Provisional cost per piece: Unresolved'),
          ReceiptSuggestionLabel(
            provenance: line.provenance[ReceiptSuggestionField.amount],
            fieldLabel: 'Amount',
            detail:
                line.extractedUnitPriceCents != null && line.quantity != null
                ? '${pesos(line.extractedUnitPriceCents!)} × ${line.quantity}'
                : null,
          ),
          ReceiptSuggestionLabel(
            provenance: line.provenance[ReceiptSuggestionField.product],
            fieldLabel: 'Product',
          ),
          ReceiptSuggestionLabel(
            provenance: line.provenance[ReceiptSuggestionField.quantity],
            fieldLabel: 'Quantity',
          ),
          ReceiptSuggestionLabel(
            provenance: line.provenance[ReceiptSuggestionField.unit],
            fieldLabel: 'Unit',
          ),
          ReceiptSuggestionLabel(
            provenance: line.provenance[ReceiptSuggestionField.piecesPerPack],
            fieldLabel: 'Pack contents',
          ),
        ],
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Raw recognized text'),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                draft.ocrPages.isEmpty
                    ? draft.textLines.map((line) => line.text).join('\n')
                    : draft.ocrPages
                          .map(
                            (page) => page.textLines
                                .map((line) => line.text)
                                .join('\n'),
                          )
                          .join('\n\n'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
