import 'package:flutter/material.dart';
import '../../../core/models/models.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/receipt_paper.dart';
import 'receipt_purchase_row.dart';
import 'receipt_images_preview.dart';

class SavedDigitalReceipt extends StatelessWidget {
  const SavedDigitalReceipt({
    super.key,
    required this.detail,
    required this.products,
    required this.onCompare,
  });
  final ReceiptDetail detail;
  final Map<String, Product> products;
  final ValueChanged<PurchaseRecord> onCompare;
  @override
  Widget build(BuildContext context) {
    final receipt = detail.receipt;
    final pieces = detail.lines.fold<int>(
      0,
      (sum, line) => sum + line.totalPieces,
    );
    return ReceiptPaper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.receipt_long_outlined,
            color: AppColors.primary,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            receipt.supplier.name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (receipt.supplier.branch.isNotEmpty)
            Text(receipt.supplier.branch, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          const Center(
            child: Chip(
              label: Text('Saved purchase'),
              avatar: Icon(Icons.check, size: 18),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Purchase date: ${purchaseDate(receipt.purchasedAt, withTime: receipt.hasPurchaseTime)}',
          ),
          if (receipt.receiptNumber.isNotEmpty)
            Text('Receipt no. ${receipt.receiptNumber}'),
          const Divider(height: 32),
          for (final line in detail.lines) ...[
            ReceiptPurchaseRow(
              line: line,
              product: products[line.productId],
              onCompare: () => onCompare(line),
            ),
            const Divider(height: 16),
          ],
          Text(
            '${detail.lines.length} items · $pieces pieces',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Text(
            'RECORDED TOTAL',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            pesos(receipt.totalCents),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Total of the saved items, after line discounts.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          if (receipt.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Notes: ${receipt.notes}'),
          ],
          const Divider(height: 32),
          ReceiptImagesPreview(paths: receipt.imagePaths),
          const SizedBox(height: 12),
          Text(
            'Saved on ${purchaseDate(receipt.createdAt, withTime: true)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
