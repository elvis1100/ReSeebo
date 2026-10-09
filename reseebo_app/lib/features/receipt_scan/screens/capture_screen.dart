import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/adapters/reseebo_data_adapter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../state/capture_state.dart';
import '../widgets/capture_page_strip.dart';
import '../widgets/crop_receipt_dialog.dart';
import '../widgets/receipt_image_viewer.dart';
import '../widgets/straighten_receipt_dialog.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    super.key,
    required this.dataAdapter,
    this.onDraftReady,
    this.onBack,
  });
  final IReseeboDataAdapter dataAdapter;
  final ValueChanged<ReceiptDraft>? onDraftReady;
  final VoidCallback? onBack;
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  late final CaptureState _state;
  @override
  void initState() {
    super.initState();
    _state = CaptureState(adapter: widget.dataAdapter);
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  Future<void> _crop() async {
    final crop = await showDialog<List<double>>(
      context: context,
      builder: (_) => CropReceiptDialog(path: _state.previewPath!),
    );
    if (crop != null && mounted) await _state.transform(crop: crop);
  }

  Future<void> _straighten() async {
    final angle = await showDialog<double>(
      context: context,
      builder: (_) => StraightenReceiptDialog(path: _state.previewPath!),
    );
    if (angle != null && angle != 0 && mounted) {
      await _state.transform(angleDegrees: angle);
    }
  }

  Future<void> _read({bool allowLowQuality = false}) async {
    final draft = await _state.recognize(allowLowQuality: allowLowQuality);
    if (draft != null && mounted) widget.onDraftReady?.call(draft);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _state,
    builder: (context, _) {
      final hasPhotos = _state.pages.isNotEmpty;
      final enabled = !_state.busy;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Scan receipt'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: enabled
                ? (widget.onBack ?? () => Navigator.of(context).maybePop())
                : null,
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              const Text(
                'Add clear photos in receipt order. Crop the background and straighten tilted lines. Reading and editing work offline.',
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  AppButton(
                    label: 'Camera',
                    icon: Icons.camera_alt_outlined,
                    onPressed: enabled
                        ? () => _state.pick(ImageSource.camera)
                        : null,
                  ),
                  AppButton(
                    label: 'Gallery',
                    icon: Icons.photo_library_outlined,
                    variant: ButtonVariant.outlined,
                    onPressed: enabled
                        ? () => _state.pick(ImageSource.gallery)
                        : null,
                  ),
                ],
              ),
              if (hasPhotos) ...[
                const SizedBox(height: AppSpacing.md),
                CapturePageStrip(
                  pages: _state.pages,
                  selectedIndex: _state.selectedIndex,
                  onSelected: _state.selectPage,
                  enabled: enabled,
                ),
                const SizedBox(height: AppSpacing.sm),
                ReceiptImageViewer(
                  key: ValueKey(_state.previewPath),
                  imagePath: _state.previewPath!,
                  imageLabel: _state.recognitionPath == null
                      ? 'Original photo'
                      : 'Adjusted preview',
                  height: 280,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.crop),
                      label: const Text('Crop'),
                      onPressed: enabled ? _crop : null,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.rotate_right),
                      label: const Text('Rotate'),
                      onPressed: enabled
                          ? () => _state.transform(rotate: true)
                          : null,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.straighten),
                      label: const Text('Straighten'),
                      onPressed: enabled ? _straighten : null,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.undo),
                      label: const Text('Reset edits'),
                      onPressed: enabled ? _state.resetEdits : null,
                    ),
                  ],
                ),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Earlier'),
                      onPressed: enabled && _state.selectedIndex > 0
                          ? () => _state.moveSelectedPage(-1)
                          : null,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Later'),
                      onPressed:
                          enabled &&
                              _state.selectedIndex < _state.pages.length - 1
                          ? () => _state.moveSelectedPage(1)
                          : null,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove page'),
                      onPressed: enabled ? _state.removeSelectedPage : null,
                    ),
                  ],
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enhance faded ink for reading'),
                  subtitle: const Text(
                    'Creates a grayscale contrast copy. Original photos stay intact.',
                  ),
                  value: _state.enhanceForOcr,
                  onChanged: enabled ? _state.setEnhanceForOcr : null,
                ),
              ],
              if (_state.notice != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(_state.notice!),
                ),
              if (_state.error != null)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.warningBg,
                    borderRadius: BorderRadius.circular(AppRadii.control),
                  ),
                  child: Text(
                    _state.error!,
                    style: const TextStyle(color: AppColors.amberText),
                  ),
                ),
              if (_state.busy)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    children: [
                      LinearProgressIndicator(),
                      SizedBox(height: AppSpacing.sm),
                      Text('Preparing and reading photos on this device...'),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Read receipt',
                icon: Icons.document_scanner_outlined,
                isFullWidth: true,
                onPressed: enabled && hasPhotos ? () => _read() : null,
              ),
              if (_state.qualityRejected)
                TextButton(
                  onPressed: enabled
                      ? () => _read(allowLowQuality: true)
                      : null,
                  child: const Text('Use photo anyway'),
                ),
              if (hasPhotos)
                TextButton.icon(
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Enter manually'),
                  onPressed: enabled
                      ? () => widget.onDraftReady?.call(_state.manualDraft())
                      : null,
                ),
            ],
          ),
        ),
      );
    },
  );
}
