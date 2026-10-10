import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';

class CaptureReceiptActions extends StatelessWidget {
  const CaptureReceiptActions({
    super.key,
    required this.enabled,
    required this.hasPhotos,
    required this.hasReview,
    required this.ocrFailed,
    required this.onRead,
    required this.onSaveReview,
    required this.onReview,
    required this.onSavePhotos,
    required this.onManual,
  });
  final bool enabled, hasPhotos, hasReview, ocrFailed;
  final VoidCallback onRead, onSaveReview, onReview, onSavePhotos, onManual;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceCard,
    child: SafeArea(
      top: false,
      minimum: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!enabled) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Preparing photos and reading on your phone…',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          AppButton(
            label: ocrFailed ? 'Retry reading' : 'Read receipt',
            variant: hasReview ? ButtonVariant.outlined : ButtonVariant.primary,
            icon: Icons.arrow_forward_rounded,
            isFullWidth: true,
            onPressed: enabled && hasPhotos ? onRead : null,
          ),
          if (hasReview) ...[
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'Save Needs review',
              icon: Icons.save_alt_rounded,
              isFullWidth: true,
              onPressed: enabled ? onSaveReview : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'Review details',
              variant: ButtonVariant.outlined,
              isFullWidth: true,
              onPressed: enabled ? onReview : null,
            ),
          ],
          if (hasPhotos)
            TextButton.icon(
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Save photos for later'),
              onPressed: enabled ? onSavePhotos : null,
            ),
          if (hasPhotos)
            TextButton.icon(
              icon: const Icon(Icons.edit_note),
              label: const Text('Enter manually instead'),
              onPressed: enabled ? onManual : null,
            ),
        ],
      ),
    ),
  );
}
