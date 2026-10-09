import 'package:flutter/material.dart';
import '../../../core/models/restock_estimate.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_card.dart';

/// Interactive card simulating retail selling price and calculating
/// gross profit (*tubo*) per piece and across the entire restocked inventory.
class ProfitTuboCard extends StatelessWidget {
  final ProfitCalculation calculation;
  final int batchPieces;
  final ValueChanged<double> onMarkupChanged;
  final ValueChanged<double?> onCustomPriceChanged;

  const ProfitTuboCard({
    super.key,
    required this.calculation,
    required this.batchPieces,
    required this.onMarkupChanged,
    required this.onCustomPriceChanged,
  });

  @override
  Widget build(BuildContext context) {
    final effectivePrice =
        calculation.ownerSetSellingPrice ?? calculation.suggestedSellingPrice;
    final totalBatchTubo = calculation.estimatedGrossProfit * batchPieces;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Price & gross profit',
                style: AppTypography.headingSmall.copyWith(fontSize: 15),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  '${CurrencyFormatter.formatPercentage(calculation.markupPercentageUsed)} markup',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),

          // Markup quick selection chips
          Row(
            children: [10.0, 15.0, 20.0, 25.0, 30.0].map((rate) {
              final isSelected =
                  (calculation.markupPercentageUsed - rate).abs() < 0.5;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.0),
                  child: InkWell(
                    onTap: () => onMarkupChanged(rate),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusXs,
                        ),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        '${rate.toInt()}%',
                        style: AppTypography.caption.copyWith(
                          color: isSelected
                              ? Colors.white
                              : AppColors.textPrimary,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.m),

          // Pricing grid: Cost / Suggested SRP / Retail Price
          Row(
            children: [
              // Unit Cost
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Unit Cost', style: AppTypography.caption),
                    const SizedBox(height: 2),
                    Text(
                      CurrencyFormatter.format(calculation.costPerPiece),
                      style: AppTypography.tableCellNumber.copyWith(
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              // Suggested SRP
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Suggested SRP', style: AppTypography.caption),
                    const SizedBox(height: 2),
                    Text(
                      CurrencyFormatter.format(
                        calculation.suggestedSellingPrice,
                      ),
                      style: AppTypography.tableCellNumber.copyWith(
                        fontSize: 16,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              // Owner's Actual Price
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your Price / Pc', style: AppTypography.caption),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: 36,
                      child: TextFormField(
                        initialValue: effectivePrice.toStringAsFixed(2),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.center,
                        style: AppTypography.tableCellNumber.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: InputDecoration(
                          prefixText: '₱',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusXs,
                            ),
                          ),
                        ),
                        onChanged: (val) {
                          final parsed = double.tryParse(val);
                          onCustomPriceChanged(parsed);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 20),

          // Profit Summary Callout Box
          Container(
            padding: const EdgeInsets.all(AppSpacing.s + 2),
            decoration: BoxDecoration(
              color: AppColors.priceCheaperBg,
              borderRadius: BorderRadius.circular(AppSpacing.radiusS),
              border: Border.all(
                color: AppColors.priceCheaper.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.payments_rounded,
                          size: 16,
                          color: AppColors.priceCheaper,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Gross profit per piece:',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.priceCheaper,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '+${CurrencyFormatter.format(calculation.estimatedGrossProfit)} / piece  (${CurrencyFormatter.formatPercentage(calculation.grossMarginPercentage)} margin)',
                      style: AppTypography.tableCellNumber.copyWith(
                        color: AppColors.priceCheaper,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                if (batchPieces > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Total batch gross profit',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.priceCheaper,
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        '+${CurrencyFormatter.format(totalBatchTubo)}',
                        style: AppTypography.tableCellNumber.copyWith(
                          color: AppColors.priceCheaper,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
