import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../models/capture_page.dart';
import '../models/receipt_photo_edits.dart';
import '../services/local_receipt_image_service.dart';

/// Edits are staged separately from CapturePage until Apply edits. Every
/// generated preview is the exact enhanced file later handed to recognition.
class ReceiptPhotoEditorState extends ChangeNotifier {
  ReceiptPhotoEditorState({required CapturePage page, LocalReceiptImageService? imageService})
    : originalPath = page.originalPath,
      editedPath = page.recognitionPath,
      enhancedPath = page.preparedPath,
      useOriginal = page.useOriginal,
      enhance = page.enhance,
      contrast = page.contrast,
      _images = imageService ?? LocalReceiptImageService();

  final String originalPath;
  final LocalReceiptImageService _images;
  final _ownedPaths = <String>{};
  String? editedPath;
  String? enhancedPath;
  bool useOriginal;
  bool enhance;
  double contrast;
  bool busy = false;
  String? error;
  bool _disposed = false;
  Set<String> _retainedPaths = {};
  String get geometryPath => editedPath ?? originalPath;
  String get previewPath => useOriginal ? originalPath : enhancedPath ?? geometryPath;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    if (enhancedPath == null) await _run(_prepare);
  }

  Future<void> _prepare() async {
    final path = await _images.prepareRecognition(geometryPath, enhance: enhance, contrast: contrast);
    _ownedPaths.add(path);
    enhancedPath = path;
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    _changed();
    try {
      await operation();
    } catch (failure) {
      error = userMessage(failure);
    } finally {
      busy = false;
      if (_disposed) {
        await _images.deleteGenerated(_ownedPaths.difference(_retainedPaths), originalPath: originalPath);
      } else {
        _changed();
      }
    }
  }

  void selectOriginal(bool original) {
    if (busy || _disposed) return;
    useOriginal = original;
    _changed();
  }

  Future<void> transform({bool rotate = false, List<double>? crop, double angleDegrees = 0}) => _run(() async {
    final previous = editedPath;
    final path = await _images.transform(geometryPath, rotate: rotate, crop: crop, angleDegrees: angleDegrees);
    _ownedPaths.add(path);
    editedPath = path;
    try {
      await _prepare();
      useOriginal = false;
    } catch (_) {
      editedPath = previous;
      rethrow;
    }
  });

  Future<void> setContrast(double value) => _run(() async {
    final previous = contrast;
    contrast = value;
    try {
      await _prepare();
      useOriginal = false;
    } catch (_) {
      contrast = previous;
      rethrow;
    }
  });

  Future<void> setEnhance(bool value) => _run(() async {
    final previous = enhance;
    enhance = value;
    try {
      await _prepare();
      useOriginal = false;
    } catch (_) {
      enhance = previous;
      rethrow;
    }
  });

  Future<void> reset() => _run(() async {
    final previous = (editedPath, contrast, enhance);
    editedPath = null;
    contrast = 1;
    enhance = true;
    try {
      await _prepare();
      useOriginal = false;
    } catch (_) {
      (editedPath, contrast, enhance) = previous;
      rethrow;
    }
  });

  ReceiptPhotoEdits? apply() {
    if (busy || _disposed || enhancedPath == null) return null;
    _retainedPaths = {if (editedPath != null) editedPath!, enhancedPath!};
    return ReceiptPhotoEdits(
      editedPath: editedPath,
      enhancedPath: enhancedPath!,
      useOriginal: useOriginal,
      enhance: enhance,
      contrast: contrast,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    if (!busy) {
      unawaited(_images.deleteGenerated(_ownedPaths.difference(_retainedPaths), originalPath: originalPath));
    }
    super.dispose();
  }
}
