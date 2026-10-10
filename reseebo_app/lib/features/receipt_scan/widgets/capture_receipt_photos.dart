import 'package:flutter/material.dart';

import '../../../core/models/ocr_engine.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../state/capture_state.dart';
import 'capture_page_strip.dart';
import 'ocr_model_picker.dart';
import 'receipt_image_viewer.dart';

/// Photo controls keep their existing ordering and editing/navigation behavior.
class CaptureReceiptPhotos extends StatelessWidget {
  const CaptureReceiptPhotos({
    super.key,
    required this.state,
    required this.enabled,
    required this.onSelectEngine,
    required this.onEditPhoto,
    required this.onChangePhotos,
  });
  final CaptureState state;
  final bool enabled;
  final Future<void> Function(OcrEngineId) onSelectEngine;
  final Future<void> Function() onEditPhoto;
  final Future<void> Function(Future<void> Function()) onChangePhotos;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OcrModelPicker(
        engines: state.engines,
        selected: state.selectedEngineId,
        results: state.presentationResults,
        onSelected: onSelectEngine,
        enabled: enabled,
      ),
      const SizedBox(height: AppSpacing.md),
      if (state.pages.length > 1) ...[
        Text(
          '${state.pages.length} photos · top to bottom',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        CapturePageStrip(
          pages: state.pages,
          selectedIndex: state.selectedIndex,
          onSelected: state.selectPage,
          enabled: enabled,
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      ReceiptImageViewer(
        key: ValueKey(state.previewPath),
        imagePath: state.previewPath!,
        scrollPageWithOneFinger: true,
        isEnhanced:
            !state.selectedPage!.useOriginal &&
            state.selectedPage!.preparedPath != null,
        showContrastControl: false,
        displayCacheWidth: 1000,
        imageLabel: state.selectedPage!.useOriginal
            ? 'Original photo'
            : 'Enhanced photo',
        height: 280,
      ),
      Wrap(
        spacing: AppSpacing.xs,
        children: [
          if (state.pages.length > 1) ...[
            TextButton.icon(
              icon: const Icon(Icons.arrow_upward_rounded),
              label: const Text('Move earlier'),
              onPressed: enabled && state.selectedIndex > 0
                  ? () => onChangePhotos(() async => state.moveSelectedPage(-1))
                  : null,
            ),
            TextButton.icon(
              icon: const Icon(Icons.arrow_downward_rounded),
              label: const Text('Move later'),
              onPressed: enabled && state.selectedIndex < state.pages.length - 1
                  ? () => onChangePhotos(() async => state.moveSelectedPage(1))
                  : null,
            ),
          ],
          TextButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove photo'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: enabled
                ? () => onChangePhotos(() async => state.removeSelectedPage())
                : null,
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      AppButton(
        label: 'Edit / enhance photo',
        icon: Icons.tune_rounded,
        variant: ButtonVariant.outlined,
        isFullWidth: true,
        onPressed: enabled ? onEditPhoto : null,
      ),
    ],
  );
}
