import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/adapters/reseebo_data_adapter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../../core/services/receipt_snapshot_codec.dart';
import '../state/capture_state.dart';
import '../state/receipt_review_state.dart';
import '../state/pending_receipt_save_command.dart';
import '../widgets/duplicate_review_dialog.dart';
import '../widgets/ocr_result_summary.dart';
import '../widgets/capture_receipt_actions.dart';
import '../widgets/capture_receipt_photos.dart';
import '../widgets/receipt_scan_steps.dart';
import '../models/receipt_photo_edits.dart';
import 'receipt_photo_editor_screen.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    super.key,
    required this.dataAdapter,
    this.onDraftReady,
    this.onReviewRequested,
    this.onPendingSaved,
    this.onOpenPendingReceipt,
    this.onBack,
    this.captureState,
  });
  final IReseeboDataAdapter dataAdapter;
  final ValueChanged<ReceiptDraft>? onDraftReady;

  /// Opens Review with a private prepared snapshot. Return owner edits on Back,
  /// or null after a completed save; the Capture route stays underneath Review.
  /// When supplied, this callback supersedes onDraftReady.
  final Future<ReceiptDraft?> Function(ReceiptDraft)? onReviewRequested;
  final ValueChanged<PendingSaveResult>? onPendingSaved;
  final ValueChanged<String>? onOpenPendingReceipt;
  final VoidCallback? onBack;
  final CaptureState? captureState;
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  late final CaptureState _state;
  ReceiptReviewState? _preparedReview;
  String? _preparedKey;
  PendingReceiptSaveCommand? _photoCommand;
  int? _photoCommandRevision;
  bool _working = false;
  String? _actionError;
  bool _hasReturnedEdits = false;
  String? _photoCommandIdentity;
  String? _manualIdentity;
  int? _manualInputRevision;

  @override
  void initState() {
    super.initState();
    _state = widget.captureState ?? CaptureState(adapter: widget.dataAdapter);
  }

  @override
  void dispose() {
    _preparedReview?.dispose();
    if (widget.captureState == null) _state.dispose();
    super.dispose();
  }

  Future<void> _editPhoto() async {
    if (!await _confirmReplacement() || !mounted) return;
    final revision = _state.inputRevision;
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
      if (_state.inputRevision != revision) _discardPrepared();
    }
  }

  Future<void> _read({bool allowLowQuality = false}) async {
    if (_working || _state.busy) return;
    if (_hasReturnedEdits && !await _confirmReplacement()) return;
    _discardPrepared();
    setState(() {
      _working = true;
      _actionError = null;
    });
    try {
      final draft = await _state.recognize(allowLowQuality: allowLowQuality);
      if (draft != null && mounted) await _prepare(draft);
    } catch (failure) {
      if (mounted) setState(() => _actionError = userMessage(failure));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _prepare(ReceiptDraft draft) async {
    final result = _state.selectedPresentationResult;
    if (result == null) return;
    if (_preparedKey == result.key && _preparedReview != null) return;
    final review = ReceiptReviewState(
      adapter: widget.dataAdapter,
      draft: draft,
    );
    await review.load();
    if (!mounted || _state.selectedPresentationResult?.key != result.key) {
      review.dispose();
      return;
    }
    _preparedReview?.dispose();
    setState(() {
      _preparedReview = review;
      _preparedKey = result.key;
      _actionError = review.error;
    });
  }

  Future<void> _selectEngine(OcrEngineId id) async {
    if (_working) return;
    if (id != _state.selectedEngineId && !await _confirmReplacement()) return;
    if (id != _state.selectedEngineId) _discardPrepared();
    setState(() {
      _working = true;
      _actionError = null;
    });
    try {
      await _state.selectEngine(id);
      if (_state.selectedPresentationResult?.draft != null && mounted) {
        await _prepare(await _state.selectedDraftSnapshotAsync());
      }
    } catch (failure) {
      if (mounted) setState(() => _actionError = userMessage(failure));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _freshSelected() async {
    try {
      if (_preparedKey == null && _manualIdentity != null) {
        if (_manualInputRevision != _state.inputRevision ||
            await _state.photoIdentity() != _manualIdentity) {
          throw StateError('Changed photos');
        }
        return;
      }
      await _state.selectedDraftSnapshotAsync();
      if (_state.selectedPresentationResult?.key != _preparedKey) {
        throw StateError('Changed photos');
      }
    } catch (_) {
      throw const ValidationException(
        'Your receipt photos changed. Check them and read the receipt again before reviewing or saving.',
      );
    }
  }

  Future<void> _reviewDetails() async {
    if (_working || _state.busy) return;
    setState(() {
      _working = true;
      _actionError = null;
    });
    try {
      await _freshSelected();
      await _openReview(_preparedReview!.draft.snapshot());
    } catch (failure) {
      if (mounted) setState(() => _actionError = userMessage(failure));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openReview(ReceiptDraft draft) async {
    final callback = widget.onReviewRequested;
    if (callback == null) {
      widget.onDraftReady?.call(draft.snapshot());
      return;
    }
    setState(() => _working = true);
    final key = _preparedKey;
    try {
      final returned = await callback(draft.snapshot());
      if (returned == null || !mounted || _preparedKey != key) return;
      final prepared = _preparedReview;
      if (prepared != null) {
        final changed =
            ReceiptSnapshotCodec().encode(prepared.draft) !=
            ReceiptSnapshotCodec().encode(returned);
        final resumed = prepared.resumeSnapshot(returned);
        prepared.dispose();
        setState(() {
          _preparedReview = resumed;
          _hasReturnedEdits = _hasReturnedEdits || changed;
        });
      }
      // Keep returned owner edits even if external files changed while Review
      // was open; freshness refusal blocks saving until an explicit replacement.
      await _freshSelected();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<bool> _confirmReplacement() async {
    if (!_hasReturnedEdits) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Replace your review edits?'),
            content: const Text(
              'Your edits are kept when you return to Photos. Replacing this result will discard those edits.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep edits'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard edits'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _discardPrepared() {
    _preparedReview?.dispose();
    _preparedReview = null;
    _preparedKey = null;
    _hasReturnedEdits = false;
    _manualIdentity = null;
    _manualInputRevision = null;
  }

  Future<void> _changePhotos(Future<void> Function() change) async {
    if (!await _confirmReplacement() || !mounted) return;
    final revision = _state.inputRevision;
    await change();
    if (_state.inputRevision != revision && mounted) setState(_discardPrepared);
  }

  Future<void> _manualReview() async {
    if (_working || _state.busy) return;
    if (_manualIdentity != null && _preparedReview != null) {
      await _reviewDetails();
      return;
    }
    if (!await _confirmReplacement() || !mounted) return;
    _discardPrepared();
    // Manual review has no OCR result to replace; its returned owner snapshot
    // stays private and the original ordered pages remain available.
    setState(() {
      _working = true;
      _actionError = null;
    });
    try {
      final review = ReceiptReviewState(
        adapter: widget.dataAdapter,
        draft: _state.manualDraft(),
      );
      final identity = await _state.photoIdentity();
      await review.load();
      if (!mounted) {
        review.dispose();
        return;
      }
      _preparedReview = review;
      _manualIdentity = identity;
      _manualInputRevision = _state.inputRevision;
      await _openReview(review.draft.snapshot());
    } catch (failure) {
      if (mounted) setState(() => _actionError = userMessage(failure));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _saveSelected() async {
    if (_working || _state.busy) return;
    setState(() {
      _working = true;
      _actionError = null;
    });
    try {
      await _freshSelected();
      final review = _preparedReview!;
      if (review.error != null) throw ValidationException(review.error!);
      final result = await review.savePending();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt saved · Needs review')),
        );
      }
      if (mounted) widget.onPendingSaved?.call(result);
    } on DuplicateReceiptException catch (duplicate) {
      if (!mounted) return;
      final separate = await showDialog<bool>(
        context: context,
        builder: (_) => DuplicateReviewDialog(
          adapter: widget.dataAdapter,
          receiptIds: duplicate.receiptIds,
          onOpenPendingReceipt: widget.onOpenPendingReceipt,
        ),
      );
      if (separate == true && mounted) {
        _preparedReview!.allowPendingDuplicate();
        setState(() => _working = false);
        await _saveSelected();
      }
    } catch (failure) {
      if (mounted) setState(() => _actionError = userMessage(failure));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _savePhotos() async {
    if (_working || _state.busy || _state.pages.isEmpty) return;
    setState(() {
      _working = true;
      _actionError = null;
    });
    try {
      if (_photoCommandRevision != _state.inputRevision) {
        _photoCommand = PendingReceiptSaveCommand(
          draft: _state.photosOnlyDraftSnapshot(),
        );
        _photoCommandRevision = _state.inputRevision;
        _photoCommandIdentity = await _state.photoIdentity();
      }
      if (await _state.photoIdentity() != _photoCommandIdentity) {
        if (!mounted) return;
        final replace = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Receipt photos changed'),
            content: const Text(
              'The photo files changed since this save was prepared. Check the current photos before starting a new save.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep reviewing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Use current photos'),
              ),
            ],
          ),
        );
        if (replace != true || !mounted) return;
        _photoCommand = PendingReceiptSaveCommand(
          draft: _state.photosOnlyDraftSnapshot(),
        );
        _photoCommandIdentity = await _state.photoIdentity();
      }
      final result = await _photoCommand!.submit(widget.dataAdapter);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt photos saved · Needs review')),
        );
      }
      if (mounted) widget.onPendingSaved?.call(result);
    } on DuplicateReceiptException catch (duplicate) {
      if (!mounted) return;
      final separate = await showDialog<bool>(
        context: context,
        builder: (_) => DuplicateReviewDialog(
          adapter: widget.dataAdapter,
          receiptIds: duplicate.receiptIds,
          onOpenPendingReceipt: widget.onOpenPendingReceipt,
        ),
      );
      if (separate == true && mounted) {
        final draft = _state.photosOnlyDraftSnapshot()..allowDuplicate = true;
        _photoCommand = PendingReceiptSaveCommand(draft: draft);
        setState(() => _working = false);
        await _savePhotos();
      }
    } catch (failure) {
      if (mounted) setState(() => _actionError = userMessage(failure));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _state,
    builder: (context, _) {
      final hasPhotos = _state.pages.isNotEmpty;
      final enabled = !_state.busy && !_working;
      final result = _state.selectedPresentationResult;
      final manualReady =
          _manualIdentity != null &&
          _manualInputRevision == _state.inputRevision;
      final review = manualReady || _preparedKey == result?.key
          ? _preparedReview
          : null;
      final hasResult =
          result != null &&
          result.error == null &&
          review != null &&
          !manualReady;
      final hasReview = hasResult || (manualReady && review != null);
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
            absorbing: !enabled,
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
                        ? () => _changePhotos(
                            () => _state.pick(ImageSource.camera),
                          )
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: hasPhotos ? 'Add photos' : 'Choose photos',
                    icon: Icons.photo_library_outlined,
                    variant: ButtonVariant.outlined,
                    isFullWidth: true,
                    onPressed: enabled
                        ? () => _changePhotos(
                            () => _state.pick(ImageSource.gallery),
                          )
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
                  if (hasPhotos)
                    CaptureReceiptPhotos(
                      state: _state,
                      enabled: enabled,
                      onSelectEngine: _selectEngine,
                      onEditPhoto: _editPhoto,
                      onChangePhotos: _changePhotos,
                    ),
                  if (hasResult) ...[
                    const SizedBox(height: AppSpacing.md),
                    OcrResultSummary(result: result, draft: review.draft),
                  ],
                  if (manualReady && review != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.lg),
                        child: Text('Manual receipt · Needs review'),
                      ),
                    ),
                  ],
                  if (_actionError != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Notice(message: _actionError!, warning: true),
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
          bottomNavigationBar: CaptureReceiptActions(
            enabled: enabled,
            hasPhotos: hasPhotos,
            hasReview: hasReview,
            ocrFailed: _state.ocrFailed,
            onRead: () => _read(),
            onSaveReview: _saveSelected,
            onReview: _reviewDetails,
            onSavePhotos: _savePhotos,
            onManual: _manualReview,
          ),
        ),
      );
    },
  );
}
