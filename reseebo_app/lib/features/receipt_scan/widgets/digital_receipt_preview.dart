import 'package:flutter/material.dart';
import '../../../core/constants/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/receipt_paper.dart';
import '../state/receipt_review_state.dart';
import 'receipt_image_viewer.dart';

/// Read-only rendering of the validated draft; amounts remain the reviewed
/// net purchase amounts. Saving and duplicate handling belong to review state.
class DigitalReceiptPreview extends StatelessWidget {
  const DigitalReceiptPreview({super.key, required this.review});
  final ReceiptReviewState review;

  Future<void> _photos(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Expanded(child: Text('Original receipt photos')),
                IconButton(
                  tooltip: 'Close photos',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final entry in review.draft.imagePaths.indexed) ...[
                  Text('Photo ${entry.$1 + 1}'),
                  const SizedBox(height: 8),
                  ReceiptImageViewer(
                    imagePath: entry.$2,
                    height: 320,
                    imageLabel: 'Original photo',
                    scrollPageWithOneFinger: true,
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _field(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      runSpacing: 4,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        Text(value),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final draft = review.draft;
    final pieces = draft.lines.fold<int>(
      0,
      (sum, line) => sum + line.totalPieces!,
    );
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipPath(
        clipper: const ReceiptPaperClipper(),
        child: ColoredBox(
          color: AppColors.surfaceCard,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
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
                  draft.supplierName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (draft.supplierBranch.trim().isNotEmpty)
                  Text(draft.supplierBranch, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                const Center(
                  child: Chip(
                    label: Text('Reviewed purchase'),
                    avatar: Icon(
                      Icons.check,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    backgroundColor: AppColors.softPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _field(
                  'Purchase date',
                  purchaseDate(
                    draft.purchasedAt!,
                    withTime: draft.hasPurchaseTime,
                  ),
                ),
                if (draft.receiptNumber.trim().isNotEmpty)
                  _field('Receipt no.', draft.receiptNumber),
                _field(
                  'Original photos',
                  '${draft.imagePaths.length} attached',
                ),
                const _ReceiptRule(),
                for (final line in draft.lines) ...[
                  _ReceiptItem(
                    line: line,
                    product: review.productFor(line.productId),
                  ),
                  const Divider(height: 24),
                ],
                const _ReceiptRule(),
                Text(
                  '${draft.lines.length} items · $pieces pieces',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(
                      'RECORDED TOTAL',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      pesos(review.lineTotalCents!),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Total of the reviewed items, after line discounts.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                if (draft.detectedTotalCents != null &&
                    review.hasTotalDifference) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Printed receipt total: ${pesos(draft.detectedTotalCents!)}',
                  ),
                  const Text('Difference checked during review.'),
                ],
                if (draft.notes.trim().isNotEmpty) ...[
                  const _ReceiptRule(),
                  Text('Notes: ${draft.notes}'),
                ],
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: review.saving ? null : () => _photos(context),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('View original receipt photos'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReceiptItem extends StatelessWidget {
  const _ReceiptItem({required this.line, required this.product});
  final ParsedLineItem line;
  final Product? product;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        product?.displayName ?? line.description,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      if (product != null && product!.displayTitle != product!.displayName)
        Text(product!.displayTitle),
      const SizedBox(height: 8),
      Wrap(
        spacing: 20,
        runSpacing: 8,
        children: [
          _detail(
            'Quantity',
            line.unit == PurchaseUnit.pack
                ? '${line.quantity} packs × ${line.piecesPerPack} pcs'
                : '${line.quantity} pieces',
          ),
          _detail(
            'Cost / piece',
            pesos(line.netAmountCents! / line.totalPieces!),
          ),
          _detail('Amount paid', pesos(line.netAmountCents!)),
        ],
      ),
      if (line.productId == null)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Will be added to your catalog',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
    ],
  );
  Widget _detail(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      Text(
        value,
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      ),
    ],
  );
}

class _ReceiptRule extends StatelessWidget {
  const _ReceiptRule();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: LayoutBuilder(
      builder: (_, constraints) => Row(
        children: List.generate(
          (constraints.maxWidth / 12).floor(),
          (_) => Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Container(height: 1, color: AppColors.border),
            ),
          ),
        ),
      ),
    ),
  );
}
