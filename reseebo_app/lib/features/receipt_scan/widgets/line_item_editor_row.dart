import 'package:flutter/material.dart';
import '../../../core/models/product.dart';
import '../../../core/models/purchase_line.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_card.dart';

/// Interactive line editor row supporting pack-to-piece conversions,
/// on-the-fly unit cost calculations, and product alias reassignment.
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
      padding: AppSpacing.compactCardPadding,
      backgroundColor: isAmbiguous
          ? AppColors.warningBg.withValues(alpha: 0.3)
          : AppColors.surfaceCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top bar: Raw OCR string + Ambiguity Badge + Delete button
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'OCR Line #${index + 1}',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Text(
                  line.rawDescription,
                  style: AppTypography.caption.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isAmbiguous) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warningBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 12,
                        color: AppColors.accentDark,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Needs Review',
                        style: AppTypography.caption.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accentDark,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppColors.textMuted,
                ),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),

          // Matched Product Selector Button
          InkWell(
            onTap: onSelectProduct,
            borderRadius: BorderRadius.circular(AppSpacing.radiusS),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s + 2,
                vertical: AppSpacing.s,
              ),
              decoration: BoxDecoration(
                color: hasProduct
                    ? AppColors.primarySurface
                    : AppColors.accentLight.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppSpacing.radiusS),
                border: Border.all(
                  color: hasProduct
                      ? AppColors.primary.withValues(alpha: 0.3)
                      : AppColors.accent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    hasProduct
                        ? Icons.check_circle_rounded
                        : Icons.help_outline_rounded,
                    size: 18,
                    color: hasProduct ? AppColors.primary : AppColors.accent,
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Text(
                      hasProduct
                          ? matchedProduct!.displayTitle
                          : 'Tap to match known product...',
                      style: AppTypography.headingSmall.copyWith(
                        fontSize: 13,
                        color: hasProduct
                            ? AppColors.primaryDark
                            : AppColors.accentDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(
                    Icons.arrow_drop_down_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),

          // Pack math & price row
          Row(
            children: [
              // Packs count input
              Expanded(
                flex: 3,
                child: _buildSmallNumberField(
                  label: 'Packs/Qty',
                  value: line.quantity.toStringAsFixed(line.quantity.truncateToDouble() == line.quantity ? 0 : 2),
                  onChanged: (val) {
                    final dVal = double.tryParse(val) ?? 1.0;
                    if (dVal > 0) onQuantityChanged(dVal);
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('×', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              // Pieces per pack
              Expanded(
                flex: 3,
                child: _buildSmallNumberField(
                  label: 'Pcs/Pack',
                  value: line.piecesPerPack.toString(),
                  onChanged: (val) {
                    final intVal = int.tryParse(val) ?? 1;
                    if (intVal > 0) onPiecesPerPackChanged(intVal);
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('=', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              // Total pieces pill
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Pcs',
                      style: AppTypography.caption.copyWith(fontSize: 10),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        '$totalPieces pcs',
                        style: AppTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              // Line total price
              Expanded(
                flex: 4,
                child: _buildSmallNumberField(
                  label: 'Total Paid (₱)',
                  value: line.netAmount.toStringAsFixed(2),
                  isDecimal: true,
                  onChanged: (val) {
                    final dVal = double.tryParse(val) ?? 0.0;
                    if (dVal >= 0) onLineTotalChanged(dVal);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const Divider(height: 12),

          // Unit cost bottom result callout
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Unit Cost: ${CurrencyFormatter.format(line.netAmount)} ÷ $totalPieces pcs',
                style: AppTypography.caption,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  '${CurrencyFormatter.format(line.estimatedCostPerPiece)} / piece',
                  style: AppTypography.tableCellNumber.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallNumberField({
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
          height: 38,
          child: TextFormField(
            initialValue: value,
            keyboardType: TextInputType.numberWithOptions(decimal: isDecimal),
            textAlign: TextAlign.center,
            style: AppTypography.tableCellNumber.copyWith(fontSize: 13),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 8,
              ),
              isDense: true,
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
