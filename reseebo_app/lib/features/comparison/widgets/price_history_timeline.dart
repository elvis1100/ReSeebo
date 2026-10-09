import 'package:flutter/material.dart';
import '../../../core/models/comparison.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/trend_badge.dart';

/// Chronological price timeline displaying price movement, hikes, and drops over time.
class PriceHistoryTimeline extends StatelessWidget {
  final List<PriceHistoryRecord> records;
  final ValueChanged<String>? onReceiptTap;

  const PriceHistoryTimeline({
    super.key,
    required this.records,
    this.onReceiptTap,
  });

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              const Icon(
                Icons.history_rounded,
                size: 40,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: AppSpacing.s),
              Text(
                'No historical purchase records found.',
                style: AppTypography.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: records.length,
      itemBuilder: (context, index) {
        final record = records[index];
        final isLast = index == records.length - 1;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Timeline connector and node
              SizedBox(
                width: 32,
                child: Column(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index == 0
                            ? AppColors.primary
                            : AppColors.surfaceSubtle,
                        border: Border.all(
                          color: AppColors.primary,
                          width: 2.5,
                        ),
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: AppColors.border,
                        ),
                      ),
                  ],
                ),
              ),

              // Record details card
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.m),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.s + 2),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceCard,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusS),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              DateFormatter.format(record.purchaseDate),
                              style: AppTypography.headingSmall.copyWith(
                                fontSize: 13,
                              ),
                            ),
                            if (record.changeFromPreviousPesos != null &&
                                record.changeFromPreviousPesos != 0)
                              TrendBadge(
                                differenceInPesos:
                                    record.changeFromPreviousPesos,
                                percentage: record.changeFromPreviousPercent,
                              )
                            else if (record.changeFromPreviousPesos == null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceSubtle,
                                  borderRadius:
                                      BorderRadius.circular(AppSpacing.radiusXs),
                                ),
                                child: Text(
                                  'Initial record',
                                  style: AppTypography.caption.copyWith(
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Unit Cost: ${CurrencyFormatter.format(record.costPerPiece)} / pc',
                              style: AppTypography.tableCellNumber.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                            InkWell(
                              onTap: () =>
                                  onReceiptTap?.call(record.sourceReceiptId),
                              child: Text(
                                'Receipt',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          record.packageDetails,
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
