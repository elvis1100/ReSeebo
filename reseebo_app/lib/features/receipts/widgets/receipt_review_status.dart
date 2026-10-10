import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class ReceiptReviewStatus extends StatelessWidget {
  const ReceiptReviewStatus({super.key});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Text(
        'Needs review',
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: AppColors.amberText),
      ),
    ),
  );
}
