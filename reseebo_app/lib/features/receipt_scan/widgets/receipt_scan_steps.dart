import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Shows the same three stages across capture and review without navigation.
class ReceiptScanSteps extends StatelessWidget {
  const ReceiptScanSteps({super.key, required this.activeStep})
    : assert(activeStep >= 0 && activeStep <= 2);

  final int activeStep;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var index = 0; index < 3; index++) ...[
        if (index > 0) const SizedBox(width: 16, child: Divider()),
        Expanded(
          child: Semantics(
            label:
                'Step ${index + 1} of 3: ${['Photos', 'Review', 'Save'][index]}',
            selected: index == activeStep,
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: index <= activeStep
                          ? AppColors.primary
                          : AppColors.surfaceSubtle,
                      shape: BoxShape.circle,
                    ),
                    child: index < activeStep
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : Text(
                            '${index + 1}',
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: index == activeStep
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                          ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    ['Photos', 'Review', 'Save'][index],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: index == activeStep
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: index <= activeStep
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ],
  );
}
