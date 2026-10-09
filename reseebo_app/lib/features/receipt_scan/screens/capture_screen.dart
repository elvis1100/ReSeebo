import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/adapters/reseebo_data_adapter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../state/capture_state.dart';
import '../widgets/capture_page_strip.dart';
import '../widgets/receipt_image_viewer.dart';
import '../widgets/receipt_scan_steps.dart';
import '../models/receipt_photo_edits.dart';
import 'receipt_photo_editor_screen.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    super.key,
    required this.dataAdapter,
    this.onDraftReady,
    this.onBack,
    this.captureState,
  });
  final IReseeboDataAdapter dataAdapter;
  final ValueChanged<ReceiptDraft>? onDraftReady;
  final VoidCallback? onBack;
  final CaptureState? captureState;
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  late final CaptureState _state;

  @override
  void initState() {
    super.initState();
    _state = widget.captureState ?? CaptureState(adapter: widget.dataAdapter);
  }

  @override
  void dispose() {
    if (widget.captureState == null) _state.dispose();
    super.dispose();
  }

  Future<void> _editPhoto() async {
    final page = _state.selectedPage;
    if (page == null || !_state.beginPhotoEdit()) return;
    ReceiptPhotoEdits? edits;
    try {
      edits = await Navigator.of(context).push<ReceiptPhotoEdits>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ReceiptPhotoEditorScreen(page: page),
        ),
      );
    } finally {
      _state.finishPhotoEdit(page, edits);
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
      return PopScope(
        canPop: enabled,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Scan receipt'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: enabled
                  ? (widget.onBack ?? () => Navigator.of(context).maybePop())
                  : null,
            ),
          ),
          body: AbsorbPointer(
            absorbing: _state.busy,
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  const ReceiptScanSteps(activeStep: 0),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    hasPhotos
                        ? 'Check your receipt photos'
                        : 'Start with a receipt photo',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    hasPhotos
                        ? 'Make sure the words and amounts are clear. You can correct everything in the next step.'
                        : 'Take a clear photo or choose one from your phone. Reseebo will read it for you.',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AppButton(
                    label: 'Take photo',
                    icon: Icons.camera_alt_outlined,
                    isFullWidth: true,
                    onPressed: enabled
                        ? () => _state.pick(ImageSource.camera)
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: hasPhotos ? 'Add photos' : 'Choose photos',
                    icon: Icons.photo_library_outlined,
                    variant: ButtonVariant.outlined,
                    isFullWidth: true,
                    onPressed: enabled
                        ? () => _state.pick(ImageSource.gallery)
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (!hasPhotos)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 52,
                              color: AppColors.primary,
                            ),
                            SizedBox(height: AppSpacing.lg),
                            Text(
                              'A clear photo helps',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            SizedBox(height: AppSpacing.sm),
                            Text(
                              'Lay the receipt flat in good light. Include the shop name, date, items, and total.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                            SizedBox(height: AppSpacing.lg),
                            Text(
                              'Long receipt? Add photos from top to bottom with a little overlap.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (hasPhotos) ...[
                    if (_state.pages.length > 1) ...[
                      Text(
                        '${_state.pages.length} photos · top to bottom',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      CapturePageStrip(
                        pages: _state.pages,
                        selectedIndex: _state.selectedIndex,
                        onSelected: _state.selectPage,
                        enabled: enabled,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    ReceiptImageViewer(
                      key: ValueKey(_state.previewPath),
                      imagePath: _state.previewPath!,
                      scrollPageWithOneFinger: true,
                      isEnhanced:
                          !_state.selectedPage!.useOriginal &&
                          _state.selectedPage!.preparedPath != null,
                      showContrastControl: false,
                      displayCacheWidth: 1000,
                      imageLabel: _state.selectedPage!.useOriginal
                          ? 'Original photo'
                          : 'Enhanced photo',
                      height: 280,
                    ),
                    Wrap(
                      spacing: AppSpacing.xs,
                      children: [
                        if (_state.pages.length > 1) ...[
                          TextButton.icon(
                            icon: const Icon(Icons.arrow_upward_rounded),
                            label: const Text('Move earlier'),
                            onPressed: enabled && _state.selectedIndex > 0
                                ? () => _state.moveSelectedPage(-1)
                                : null,
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.arrow_downward_rounded),
                            label: const Text('Move later'),
                            onPressed:
                                enabled &&
                                    _state.selectedIndex <
                                        _state.pages.length - 1
                                ? () => _state.moveSelectedPage(1)
                                : null,
                          ),
                        ],
                        TextButton.icon(
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove photo'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.danger,
                          ),
                          onPressed: enabled ? _state.removeSelectedPage : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      label: 'Edit / enhance photo',
                      icon: Icons.tune_rounded,
                      variant: ButtonVariant.outlined,
                      isFullWidth: true,
                      onPressed: enabled ? _editPhoto : null,
                    ),
                  ],
                  if (_state.notice != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Notice(message: _state.notice!),
                  ],
                  if (_state.error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Notice(message: _state.error!, warning: true),
                  ],
                  if (_state.qualityRejected)
                    TextButton(
                      onPressed: enabled
                          ? () => _read(allowLowQuality: true)
                          : null,
                      child: const Text('Use photo anyway'),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
          bottomNavigationBar: Material(
            color: AppColors.surfaceCard,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_state.busy) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: AppSpacing.sm),
                    const Text(
                      'Preparing photos and reading on your phone…',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  AppButton(
                    label: 'Read receipt',
                    icon: Icons.arrow_forward_rounded,
                    isFullWidth: true,
                    onPressed: enabled && hasPhotos ? () => _read() : null,
                  ),
                  if (hasPhotos)
                    TextButton.icon(
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Enter manually instead'),
                      onPressed: enabled
                          ? () =>
                                widget.onDraftReady?.call(_state.manualDraft())
                          : null,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
