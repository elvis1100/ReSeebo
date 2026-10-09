import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../state/capture_state.dart';
import '../widgets/capture_page_strip.dart';
import '../widgets/crop_receipt_dialog.dart';
import '../widgets/receipt_image_viewer.dart';
import 'review_match_screen.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    super.key,
    required this.adapter,
    this.initialImagePath,
  });
  final IReseeboDataAdapter adapter;
  final String? initialImagePath;
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  late final CaptureState _state;
  bool _reviewOpen = false, _canLeave = false, _exitDialogOpen = false;
  @override
  void initState() {
    super.initState();
    _state = CaptureState(
      adapter: widget.adapter,
      initialImagePath: widget.initialImagePath,
    );
  }

  Future<void> _review({bool manual = false}) async {
    if (_reviewOpen || _state.busy || _state.pages.isEmpty) return;
    final draft = manual ? _state.manualDraft() : await _state.recognize();
    if (!mounted || draft == null) return;
    setState(() => _reviewOpen = true);
    final saved = await Navigator.push<SaveReceiptResult>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReviewMatchScreen(adapter: widget.adapter, draft: draft),
      ),
    );
    if (!mounted) return;
    setState(() => _reviewOpen = false);
    if (saved != null) {
      setState(() => _canLeave = true);
      Navigator.pop(context, saved);
    }
  }

  Future<void> _crop() async {
    if (_state.busy || _state.previewPath == null) return;
    final crop = await showDialog<List<double>>(
      context: context,
      builder: (_) => CropReceiptDialog(path: _state.previewPath!),
    );
    if (crop != null && mounted) await _state.transform(crop: crop);
  }

  Future<void> _remove() async {
    if (_state.busy || _state.pages.isEmpty) return;
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove page ${_state.selectedIndex + 1}?'),
        content: const Text(
          'This photo will be removed from the receipt draft. Check that every purchase line remains covered by the other photos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep photo'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove photo'),
          ),
        ],
      ),
    );
    if (remove == true && mounted) _state.removeSelectedPage();
  }

  Future<void> _requestExit() async {
    if (_state.busy || _reviewOpen || _exitDialogOpen) return;
    _exitDialogOpen = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard receipt photos?'),
        content: const Text('These photos have not been saved as a purchase.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep scanning'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    _exitDialogOpen = false;
    if (discard == true && mounted) {
      setState(() => _canLeave = true);
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _state,
    builder: (context, _) {
      final busy = _state.busy || _reviewOpen;
      final pages = _state.pages;
      return PopScope(
        canPop: !busy && (_canLeave || pages.isEmpty),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _requestExit();
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('Scan a receipt')),
          body: ListView(
            padding: AppSpacing.page,
            children: [
              Text(
                'One receipt, all its pages',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Take clear photos from top to bottom or import several photos. Arrange them in reading order before recognition.',
              ),
              const SizedBox(height: AppSpacing.lg),
              if (pages.isEmpty)
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    color: AppColors.softPrimary,
                    borderRadius: BorderRadius.circular(AppRadii.hero),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.document_scanner_outlined,
                      size: 64,
                      color: AppColors.primary,
                    ),
                  ),
                )
              else ...[
                Text(
                  '${pages.length} ${pages.length == 1 ? 'photo' : 'photos'} · one purchase',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                CapturePageStrip(
                  pages: pages,
                  selectedIndex: _state.selectedIndex,
                  enabled: !busy,
                  onSelected: _state.selectPage,
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  height: 240,
                  child: Image.file(
                    File(_state.previewPath!),
                    fit: BoxFit.contain,
                    cacheWidth: 1000,
                    semanticLabel:
                        'Receipt photo, page ${_state.selectedIndex + 1}',
                    errorBuilder: (_, _, _) => const Center(
                      child: Text(
                        'Could not open this photo. Remove it and choose another.',
                      ),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => openReceiptImages(
                          context,
                          pages.map((page) => page.originalPath).toList(),
                          initialPage: _state.selectedIndex,
                        ),
                  icon: const Icon(Icons.zoom_in),
                  label: const Text('Open original photo'),
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => _state.transform(rotate: true),
                      icon: const Icon(Icons.rotate_right),
                      label: const Text('Rotate'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _crop,
                      icon: const Icon(Icons.crop),
                      label: const Text('Crop'),
                    ),
                    if (_state.recognitionPath != null)
                      TextButton(
                        onPressed: busy ? null : _state.resetEdits,
                        child: const Text('Reset edits'),
                      ),
                  ],
                ),
                if (_state.recognitionPath != null)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      'The adjusted copy is used for recognition. Your original is preserved.',
                    ),
                  ),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    TextButton.icon(
                      onPressed: !busy && _state.selectedIndex > 0
                          ? () => _state.moveSelectedPage(-1)
                          : null,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Move earlier'),
                    ),
                    TextButton.icon(
                      onPressed:
                          !busy && _state.selectedIndex + 1 < pages.length
                          ? () => _state.moveSelectedPage(1)
                          : null,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Move later'),
                    ),
                    TextButton.icon(
                      onPressed: busy ? null : _remove,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove page'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy || pages.length >= maxReceiptPages
                        ? null
                        : () => _state.pick(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Add camera photo'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy || pages.length >= maxReceiptPages
                        ? null
                        : () => _state.pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Import photos'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const Notice(
                message:
                    'All photos are saved with one receipt. Recognition runs on your phone; review product matches and any repeated rows before saving.',
              ),
              if (_state.notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Notice(message: _state.notice!),
                ),
              if (_state.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Notice(message: _state.error!, warning: true),
                ),
              const SizedBox(height: AppSpacing.xl),
              AppActionButton(
                label: 'Recognize receipt',
                icon: Icons.document_scanner,
                busy: busy,
                busyLabel: 'Processing on your phone…',
                onPressed: pages.isEmpty ? null : _review,
              ),
              if (_state.ocrFailed)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: OutlinedButton(
                    onPressed: busy ? null : () => _review(manual: true),
                    child: const Text('Enter details from original receipt'),
                  ),
                ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      );
    },
  );
}
