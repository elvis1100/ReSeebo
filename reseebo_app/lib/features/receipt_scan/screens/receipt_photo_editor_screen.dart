import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../models/capture_page.dart';
import '../state/receipt_photo_editor_state.dart';
import '../widgets/crop_receipt_dialog.dart';
import '../widgets/receipt_image_viewer.dart';
import '../widgets/straighten_receipt_dialog.dart';

class ReceiptPhotoEditorScreen extends StatefulWidget {
  const ReceiptPhotoEditorScreen({
    super.key,
    required this.page,
    this.editorState,
  });

  final CapturePage page;
  final ReceiptPhotoEditorState? editorState;

  @override
  State<ReceiptPhotoEditorScreen> createState() =>
      _ReceiptPhotoEditorScreenState();
}

class _ReceiptPhotoEditorScreenState extends State<ReceiptPhotoEditorScreen> {
  late final ReceiptPhotoEditorState _state;
  bool _dialogOpen = false;
  bool _photoInteracting = false;
  double? _sliderContrast;

  @override
  void initState() {
    super.initState();
    _state = widget.editorState ?? ReceiptPhotoEditorState(page: widget.page);
    _state.initialize();
  }

  @override
  void dispose() {
    if (widget.editorState == null) _state.dispose();
    super.dispose();
  }

  Future<void> _crop() async {
    if (!_controlsEnabled) return;
    setState(() => _dialogOpen = true);
    final crop = await showDialog<List<double>>(
      context: context,
      builder: (_) => CropReceiptDialog(path: _state.geometryPath),
    );
    if (!mounted) return;
    setState(() => _dialogOpen = false);
    if (crop != null) await _state.transform(crop: crop);
  }

  Future<void> _straighten() async {
    if (!_controlsEnabled) return;
    setState(() => _dialogOpen = true);
    final angle = await showDialog<double>(
      context: context,
      builder: (_) => StraightenReceiptDialog(path: _state.geometryPath),
    );
    if (!mounted) return;
    setState(() => _dialogOpen = false);
    if (angle != null && angle != 0) {
      await _state.transform(angleDegrees: angle);
    }
  }

  Future<void> _setContrast(double value) async {
    if (!_controlsEnabled) return;
    await _state.setContrast(value);
    if (mounted) setState(() => _sliderContrast = null);
  }

  void _setPhotoInteraction(bool active) {
    if (mounted && _photoInteracting != active) {
      setState(() {
        _photoInteracting = active;
        if (active) _sliderContrast = null;
      });
    }
  }

  bool get _controlsEnabled =>
      !_state.busy && !_dialogOpen && !_photoInteracting;

  void _apply() {
    if (!_controlsEnabled) return;
    final edits = _state.apply();
    if (edits != null) Navigator.pop(context, edits);
  }

  void _cancel() {
    if (_controlsEnabled) Navigator.pop(context);
  }

  Future<void> _performEdit(Future<void> Function() operation) async {
    if (_controlsEnabled) await operation();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _state,
    builder: (context, _) {
      final processing = _state.busy || _dialogOpen;
      final enabled = _controlsEnabled;
      return PopScope(
        canPop: enabled,
        child: Scaffold(
          backgroundColor: AppColors.textPrimary,
          appBar: AppBar(
            backgroundColor: AppColors.textPrimary,
            foregroundColor: Colors.white,
            titleTextStyle: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: Colors.white),
            title: const Text('Edit photo'),
            leading: IconButton(
              tooltip: 'Cancel edits',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: enabled ? _cancel : null,
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: IconButton.filled(
                  tooltip: 'Apply edits',
                  icon: const Icon(Icons.check_rounded),
                  onPressed: enabled && _state.enhancedPath != null
                      ? _apply
                      : null,
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (_state.busy) const LinearProgressIndicator(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: AbsorbPointer(
                      // Active photo gestures must still receive pointer-up;
                      // only competing controls are disabled until they finish.
                      absorbing: processing,
                      child: LayoutBuilder(
                        builder: (context, constraints) => ReceiptImageViewer(
                          key: ValueKey(_state.previewPath),
                          imagePath: _state.previewPath,
                          height: constraints.maxHeight,
                          showContrastControl: false,
                          displayCacheWidth: 1600,
                          imageLabel: _state.useOriginal
                              ? 'Original photo'
                              : 'Enhanced photo',
                          isEnhanced:
                              !_state.useOriginal &&
                              _state.enhancedPath != null,
                          onInteractionActiveChanged: _setPhotoInteraction,
                          topOverlay: Material(
                            color: AppColors.surfaceCard.withValues(alpha: .95),
                            borderRadius: BorderRadius.circular(
                              AppRadii.control,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: AppSpacing.md,
                                right: AppSpacing.xs,
                              ),
                              child: MergeSemantics(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Flexible(
                                      child: Text(
                                        'Enhance photo',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Switch.adaptive(
                                      key: const ValueKey(
                                        'receipt-photo-enhancement',
                                      ),
                                      value: !_state.useOriginal,
                                      onChanged: enabled
                                          ? (value) {
                                              if (_controlsEnabled) {
                                                _state.selectOriginal(!value);
                                              }
                                            }
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Controls stay outside the photo and can scroll independently
                // when larger text would otherwise hide part of the receipt.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .4,
                  ),
                  child: Material(
                    color: AppColors.surfaceCard,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadii.hero),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.sm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.danger,
                                side: BorderSide(
                                  color: AppColors.danger.withValues(alpha: .5),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                  vertical: AppSpacing.sm,
                                ),
                              ),
                              onPressed: enabled
                                  ? () => _performEdit(_state.reset)
                                  : null,
                              icon: const Icon(
                                Icons.settings_backup_restore_rounded,
                              ),
                              label: const Text('Reset edits'),
                            ),
                          ),
                          Wrap(
                            spacing: AppSpacing.xs,
                            alignment: WrapAlignment.center,
                            children: [
                              TextButton.icon(
                                onPressed: enabled ? _crop : null,
                                icon: const Icon(Icons.crop),
                                label: const Text('Crop'),
                              ),
                              TextButton.icon(
                                onPressed: enabled
                                    ? () => _performEdit(
                                        () => _state.transform(rotate: true),
                                      )
                                    : null,
                                icon: const Icon(Icons.rotate_right),
                                label: const Text('Rotate'),
                              ),
                              TextButton.icon(
                                onPressed: enabled ? _straighten : null,
                                icon: const Icon(Icons.straighten),
                                label: const Text('Straighten'),
                              ),
                            ],
                          ),
                          SwitchListTile.adaptive(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Make faded text clearer'),
                            value: _state.enhance,
                            onChanged: enabled
                                ? (value) => _performEdit(
                                    () => _state.setEnhance(value),
                                  )
                                : null,
                          ),
                          Row(
                            children: [
                              Text(
                                'Contrast',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Expanded(
                                child: Slider(
                                  value: _sliderContrast ?? _state.contrast,
                                  min: .5,
                                  max: 2,
                                  divisions: 15,
                                  label:
                                      '${(_sliderContrast ?? _state.contrast).toStringAsFixed(1)}×',
                                  onChanged: enabled
                                      ? (value) => setState(
                                          () => _sliderContrast = value,
                                        )
                                      : null,
                                  onChangeEnd: enabled ? _setContrast : null,
                                ),
                              ),
                            ],
                          ),
                          if (_state.error != null)
                            Notice(message: _state.error!, warning: true),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
