import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../models/capture_page.dart';
import '../models/receipt_photo_edits.dart';
import '../services/local_receipt_image_service.dart';

class CaptureState extends ChangeNotifier {
  CaptureState({
    required this.adapter,
    String? initialImagePath,
    LocalReceiptImageService? imageService,
    ImagePicker? picker,
  }) : _images = imageService ?? LocalReceiptImageService(),
       _picker = picker ?? ImagePicker() {
    if (initialImagePath != null) {
      _pages.add(CapturePage(originalPath: initialImagePath));
    }
  }
  final IReseeboDataAdapter adapter;
  final LocalReceiptImageService _images;
  final ImagePicker _picker;
  final List<CapturePage> _pages = [];
  List<CapturePage> get pages => List.unmodifiable(_pages);
  int selectedIndex = 0;
  CapturePage? get selectedPage =>
      _pages.isEmpty ? null : _pages[selectedIndex];
  String? get originalPath => selectedPage?.originalPath;
  String? get recognitionPath => selectedPage?.recognitionPath;
  String? get previewPath => selectedPage?.previewPath;
  String? error;
  String? notice;
  bool busy = false;
  bool ocrFailed = false;
  bool qualityRejected = false;
  bool _defaultEnhance = true;
  bool get enhanceForOcr => selectedPage?.enhance ?? _defaultEnhance;
  bool _editorOpen = false;
  bool _draftProduced = false;
  bool _disposed = false;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> pick(ImageSource source) async {
    if (busy) return;
    busy = true;
    error = null;
    notice = null;
    _changed();
    try {
      final photos = source == ImageSource.gallery
          ? await _picker.pickMultiImage(imageQuality: 95)
          : [
              await _picker.pickImage(
                source: ImageSource.camera,
                imageQuality: 95,
              ),
            ].whereType<XFile>().toList();
      await _append(photos.map((photo) => photo.path));
    } catch (failure) {
      error = failure is AppException
          ? failure.message
          : 'Could not add photos. Check camera/photo access in phone settings and try again.';
    } finally {
      busy = false;
      _changed();
    }
  }

  /// Input ordering is preserved. Identical original bytes are included once,
  /// even when the picker returns different cache paths for the same photo.
  Future<void> addImages(List<String> paths) async {
    if (busy) return;
    busy = true;
    error = null;
    notice = null;
    _changed();
    try {
      await _append(paths);
    } catch (failure) {
      error = userMessage(failure);
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> _append(Iterable<String> paths) async {
    final knownHashes = <String>{};
    for (final page in _pages) {
      page.originalHash ??= await _images.hash(page.originalPath);
      knownHashes.add(page.originalHash!);
    }
    var skipped = 0;
    for (final path in paths) {
      final hash = await _images.hash(path);
      if (!knownHashes.add(hash)) {
        skipped++;
        continue;
      }
      if (_pages.length >= maxReceiptPages) {
        throw const AppException(
          'Use no more than $maxReceiptPages photos for one receipt.',
        );
      }
      final page = CapturePage(originalPath: path, originalHash: hash)
        ..enhance = _defaultEnhance;
      page.preparedPath = await _images.prepareRecognition(
        path,
        enhance: page.enhance,
      );
      _pages.add(page);
      selectedIndex = _pages.length - 1;
      ocrFailed = false;
      qualityRejected = false;
    }
    if (skipped > 0) {
      notice =
          'Skipped $skipped duplicate ${skipped == 1 ? 'photo' : 'photos'}. Each original page is included once.';
    }
  }

  void selectPage(int index) {
    if (busy || index < 0 || index >= _pages.length) return;
    selectedIndex = index;
    _changed();
  }

  void moveSelectedPage(int offset) {
    if (busy || _pages.isEmpty) return;
    final next = selectedIndex + offset;
    if (next < 0 || next >= _pages.length) return;
    final page = _pages.removeAt(selectedIndex);
    _pages.insert(next, page);
    selectedIndex = next;
    error = null;
    _changed();
  }

  void removeSelectedPage() {
    if (busy || _pages.isEmpty) return;
    final removed = _pages.removeAt(selectedIndex);
    unawaited(
      _images.deleteGenerated([
        removed.recognitionPath,
        removed.preparedPath,
        removed.originalPreparedPath,
      ], originalPath: removed.originalPath),
    );
    selectedIndex = _pages.isEmpty
        ? 0
        : selectedIndex.clamp(0, _pages.length - 1);
    error = null;
    notice = null;
    ocrFailed = false;
    qualityRejected = false;
    _changed();
  }

  Future<void> transform({
    bool rotate = false,
    List<double>? crop,
    double angleDegrees = 0,
  }) async {
    final page = selectedPage;
    if (busy || page == null) return;
    busy = true;
    error = null;
    _changed();
    try {
      page.recognitionPath = await _images.transform(
        page.editedPath,
        rotate: rotate,
        crop: crop,
        angleDegrees: angleDegrees,
      );
      page.preparedPath = await _images.prepareRecognition(
        page.editedPath,
        enhance: page.enhance,
        contrast: page.contrast,
      );
      page.useOriginal = false;
      qualityRejected = false;
      ocrFailed = false;
    } catch (failure) {
      error = userMessage(failure);
    } finally {
      busy = false;
      _changed();
    }
  }

  void resetEdits() {
    if (busy || selectedPage == null) return;
    selectedPage!.recognitionPath = null;
    selectedPage!.preparedPath = null;
    qualityRejected = false;
    error = null;
    _changed();
  }

  void setEnhanceForOcr(bool enabled) {
    if (busy || enhanceForOcr == enabled) return;
    _defaultEnhance = enabled;
    for (final page in _pages) {
      unawaited(
        _images.deleteGenerated([
          page.preparedPath,
        ], originalPath: page.originalPath),
      );
      page.enhance = enabled;
      page.preparedPath = null;
    }
    _changed();
  }

  /// Locks selection, additions, removal and recognition while the editor is
  /// open. The page itself is unchanged until a successful Apply edits result.
  bool beginPhotoEdit() {
    if (busy || _disposed || selectedPage == null) return false;
    _editorOpen = true;
    busy = true;
    _changed();
    return true;
  }

  void finishPhotoEdit(CapturePage page, ReceiptPhotoEdits? edits) {
    if (!_editorOpen) return;
    _editorOpen = false;
    if (edits != null && !_disposed && _pages.contains(page)) {
      final obsolete = [
        page.recognitionPath,
        page.preparedPath,
      ].where((path) => path != edits.editedPath && path != edits.enhancedPath);
      unawaited(
        _images.deleteGenerated(obsolete, originalPath: page.originalPath),
      );
      page.recognitionPath = edits.editedPath;
      page.preparedPath = edits.enhancedPath;
      page.useOriginal = edits.useOriginal;
      page.enhance = edits.enhance;
      page.contrast = edits.contrast;
      error = null;
      qualityRejected = false;
      ocrFailed = false;
    }
    busy = false;
    _changed();
  }

  Future<ReceiptDraft?> recognize({bool allowLowQuality = false}) async {
    if (busy || _pages.isEmpty) return null;
    busy = true;
    error = null;
    ocrFailed = false;
    qualityRejected = false;
    _changed();
    try {
      for (var index = 0; index < _pages.length; index++) {
        final page = _pages[index];
        final quality = await _images.inspectQuality(
          page.useOriginal ? page.originalPath : page.editedPath,
        );
        if (quality.needsRetake && !allowLowQuality) {
          qualityRejected = true;
          selectedIndex = index;
          throw AppException(
            'Page ${index + 1} looks blurred, faint, or too small. Hold steady in brighter light, crop the receipt, or choose Use photo anyway.',
          );
        }
        if (page.useOriginal) {
          page.originalPreparedPath ??= await _images.prepareRecognition(
            page.originalPath,
            enhance: false,
          );
        } else {
          page.preparedPath ??= await _images.prepareRecognition(
            page.editedPath,
            enhance: page.enhance,
            contrast: page.contrast,
          );
        }
      }
      final draft = await adapter.processReceiptImages(
        _pages.map((page) => page.originalPath).toList(),
        recognitionImagePaths: _pages
            .map(
              (page) => page.useOriginal
                  ? page.originalPreparedPath!
                  : page.preparedPath!,
            )
            .toList(),
      );
      _draftProduced = true;
      return draft;
    } catch (failure) {
      error = userMessage(failure);
      ocrFailed = true;
      return null;
    } finally {
      busy = false;
      _changed();
    }
  }

  ReceiptDraft manualDraft() => ReceiptDraft(
    imagePath: _pages.first.originalPath,
    imagePaths: _pages.map((page) => page.originalPath).toList(),
    warnings: ['Enter and confirm the information from every original page.'],
  );
  @override
  void dispose() {
    _disposed = true;
    if (!busy && !_draftProduced) {
      for (final page in _pages) {
        unawaited(
          _images.deleteGenerated([
            page.recognitionPath,
            page.preparedPath,
            page.originalPreparedPath,
          ], originalPath: page.originalPath),
        );
      }
    }
    super.dispose();
  }
}
