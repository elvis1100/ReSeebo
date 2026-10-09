import 'package:flutter/material.dart';
import '../../../core/models/product.dart';
import '../../../core/models/purchase_line.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_card.dart';

/// Clean, high-density line item editor following modern fintech design standards.
///
/// Removes arithmetic equation glyphs (`×`, `=`) and reduces visual noise,
/// focusing on fast verification and clear price-per-piece outcomes.
class LineItemEditorRow extends StatelessWidget {
  final ParsedLineItem line;
  final Product? matchedProduct;
  final int index;
  final VoidCallback onSelectProduct;
  final ValueChanged<double> onQuantityChanged;
  final ValueChanged<int> onPiecesPerPackChanged;
  final ValueChanged<double> onLineTotalChanged;
  final VoidCallback onRemove;

  const LineItemEditorRow({
    super.key,
    required this.line,
    this.matchedProduct,
    required this.index,
    required this.onSelectProduct,
    required this.onQuantityChanged,
    required this.onPiecesPerPackChanged,
    required this.onLineTotalChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final hasProduct = matchedProduct != null;
    final isAmbiguous = line.isAmbiguous || !hasProduct;
    final totalPieces = (line.quantity * (line.piecesPerPack <= 0 ? 1 : line.piecesPerPack)).round();

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.s + 2,
      ),
      backgroundColor: AppColors.surfaceCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top: Title, matched product, and line total
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: onSelectProduct,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              hasProduct
                                  ? matchedProduct!.displayTitle
                                  : 'Tap to match product',
                              style: AppTypography.headingSmall.copyWith(
                                fontSize: 14,
                                color: hasProduct
                                    ? AppColors.textPrimary
                                    : AppColors.accent,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_drop_down_rounded,
                            size: 18,
                            color: hasProduct
                                ? AppColors.textSecondary
                                : AppColors.accent,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'OCR: "${line.rawDescription}"',
                      style: AppTypography.caption.copyWith(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.format(line.netAmount),
                    style: AppTypography.tableCellNumber.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (isAmbiguous)
                    Text(
                      'Unmatched',
                      style: AppTypography.caption.copyWith(
                        fontSize: 10,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 4),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                onPressed: onRemove,
              ),
            ],
          ),
          const Divider(height: 16),

          // Middle: Clean input fields without math symbols
          Row(
            children: [
              Expanded(
                child: _buildCompactField(
                  label: 'Packs / Qty',
                  value: line.quantity.toStringAsFixed(
                    line.quantity.truncateToDouble() == line.quantity ? 0 : 2,
                  ),
                  onChanged: (val) {
                    final d = double.tryParse(val) ?? 1.0;
                    if (d > 0) onQuantityChanged(d);
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: _buildCompactField(
                  label: 'Pcs / Pack',
                  value: line.piecesPerPack.toString(),
                  onChanged: (val) {
                    final i = int.tryParse(val) ?? 1;
                    if (i > 0) onPiecesPerPackChanged(i);
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: _buildCompactField(
                  label: 'Line Total (₱)',
                  value: line.netAmount.toStringAsFixed(2),
                  isDecimal: true,
                  onChanged: (val) {
                    final d = double.tryParse(val) ?? 0.0;
                    if (d >= 0) onLineTotalChanged(d);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),

          // Bottom: Clean calculated outcome
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$totalPieces total pieces',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${CurrencyFormatter.format(line.estimatedCostPerPiece)} / piece',
                style: AppTypography.tableCellNumber.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactField({
    required String label,
    required String value,
    bool isDecimal = false,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(fontSize: 10),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 34,
          child: TextFormField(
            initialValue: value,
            keyboardType: TextInputType.numberWithOptions(decimal: isDecimal),
            textAlign: TextAlign.center,
            style: AppTypography.tableCellNumber.copyWith(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 6,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
              ),
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
