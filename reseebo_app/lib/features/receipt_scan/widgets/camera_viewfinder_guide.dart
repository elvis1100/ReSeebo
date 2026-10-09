import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// Semi-transparent framing overlay with guidelines to assist the sari-sari
/// store owner in aligning physical thermal or wholesale paper receipts.
class CameraViewfinderGuide extends StatelessWidget {
  const CameraViewfinderGuide({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.maxWidth * 0.86;
        final boxHeight = constraints.maxHeight * 0.65;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Darkened scrim surrounding the cutout
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.6),
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.transparent,
                    ),
                    width: double.infinity,
                    height: double.infinity,
                  ),
                  Center(
                    child: Container(
                      width: boxWidth,
                      height: boxHeight,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusM),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Corner border accents highlighting the target receipt area
            Center(
              child: Container(
                width: boxWidth,
                height: boxHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusM),
                  border: Border.all(
                    color: AppColors.accentLight.withValues(alpha: 0.7),
                    width: 1.5,
                  ),
                ),
                child: Stack(
                  children: [
                    // Top-left corner mark
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: AppColors.primaryLight, width: 4),
                            left: BorderSide(color: AppColors.primaryLight, width: 4),
                          ),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(AppSpacing.radiusM),
                          ),
                        ),
                      ),
                    ),
                    // Top-right corner mark
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: AppColors.primaryLight, width: 4),
                            right: BorderSide(color: AppColors.primaryLight, width: 4),
                          ),
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(AppSpacing.radiusM),
                          ),
                        ),
                      ),
                    ),
                    // Bottom-left corner mark
                    Positioned(
                      bottom: 0,
                      left: 0,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: AppColors.primaryLight, width: 4),
                            left: BorderSide(color: AppColors.primaryLight, width: 4),
                          ),
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(AppSpacing.radiusM),
                          ),
                        ),
                      ),
                    ),
                    // Bottom-right corner mark
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: AppColors.primaryLight, width: 4),
                            right: BorderSide(color: AppColors.primaryLight, width: 4),
                          ),
                          borderRadius: BorderRadius.only(
                            bottomRight: Radius.circular(AppSpacing.radiusM),
                          ),
                        ),
                      ),
                    ),

                    // Center guidance text
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.m,
                          vertical: AppSpacing.s,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(AppSpacing.radiusS),
                        ),
                        child: Text(
                          'Align receipt within frame\nFlatten edges & avoid bright glare',
                          textAlign: TextAlign.center,
                          style: AppTypography.caption.copyWith(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
