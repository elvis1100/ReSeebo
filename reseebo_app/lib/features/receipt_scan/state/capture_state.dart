import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/adapters/i_reseebo_data_adapter.dart';
import '../../../core/services/receipt_parser.dart';
import '../models/capture_page.dart';
import '../models/receipt_photo_edits.dart';
import '../models/scan_result.dart';
import '../services/local_receipt_image_service.dart';
import '../services/scan_result_cache.dart';

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
    _engineLoad = _loadEngines();
  }
  final IReseeboDataAdapter adapter;
  final LocalReceiptImageService _images;
  final ImagePicker _picker;
  final ScanResultCache _cache = ScanResultCache();
  final Map<OcrEngineId, ScanResult> _presentationResults = {};
  final Map<String, String> _sourceHashes = {};
  final Map<String, String> _preparedSources = {};
  // A newly observed original hash never authenticates an existing derivative.
  // Record the original identity before generation or editor entry instead.
  final Map<String, String> _derivedOriginalHashes = {};
  final Map<String, int> _editRevisions = {};
  final Map<String, String> _generatedPaths = {};
  final Set<String> _handedOffPaths = {};
  late final Future<void> _engineLoad;
  List<OcrEngineDescriptor> _engines = [];
  List<OcrEngineDescriptor> get engines => List.unmodifiable(_engines);
  OcrEngineId _selectedEngineId = OcrEngineId.mlKit;
  OcrEngineId get selectedEngineId => _selectedEngineId;

  /// Display-only results last validated asynchronously. These accessors do no
  /// file I/O; Review/Save must use the fresh snapshot methods below.
  Map<OcrEngineId, ScanResult> get presentationResults =>
      Map.unmodifiable(_presentationResults);
  ScanResult? get selectedPresentationResult =>
      _presentationResults[selectedEngineId];
  int get inputRevision => _generation;

  /// Photos-only/manual commands freeze this ordered actual-byte identity.
  /// Call outside build and again before retry; changed evidence needs a new
  /// command instead of repointing a frozen request at different photo bytes.
  Future<String> photoIdentity() async {
    final generation = _generation;
    final photos = List.of(_pages);
    final identity = <Object>[];
    for (final page in photos) {
      identity.add([
        await _images.hash(page.originalPath),
        _editIdentity(page),
      ]);
    }
    if (_disposed || generation != _generation) {
      throw StateError(
        'The receipt photos changed while preparing this action.',
      );
    }
    return sha256.convert(utf8.encode(jsonEncode(identity))).toString();
  }

  static const preprocessingRevision = '1';
  int _generation = 0;
  int _selectionGeneration = 0;
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
  String? _editorOriginalHash;
  String? _editorGeometryPath;
  String? _editorGeometryHash;
  bool _disposed = false;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _loadEngines() async {
    try {
      final descriptors = await adapter.getOcrEngines();
      if (_disposed) return;
      _engines = List.unmodifiable(descriptors);
      _changed();
    } catch (failure) {
      if (!_disposed) {
        error = userMessage(failure);
        _changed();
      }
    }
  }

  OcrEngineDescriptor? _descriptor(OcrEngineId id) =>
      _engines.where((engine) => engine.id == id).firstOrNull;

  String _editIdentity(CapturePage page) => jsonEncode([
    _editRevisions[page.id] ?? 0,
    page.useOriginal,
    page.enhance,
    page.contrast,
  ]);

  List<String> get _recognitionInputs => _pages
      .map(
        (page) =>
            page.useOriginal ? page.originalPreparedPath! : page.preparedPath!,
      )
      .toList();
  List<String> get _comparisonInputs => _pages
      .map(
        (page) =>
            page.useOriginal ? page.originalPreparedPath! : page.editedPath,
      )
      .toList();

  bool get _inputsPrepared =>
      _pages.isNotEmpty &&
      _pages.every(
        (page) => page.useOriginal
            ? page.originalPreparedPath != null
            : page.preparedPath != null,
      );

  Future<String> _keyFor(OcrEngineDescriptor engine) => ScanResultCache.keyFor(
    originalPaths: _pages.map((page) => page.originalPath).toList(),
    recognitionPaths: _recognitionInputs,
    comparisonPaths: _comparisonInputs,
    photoEditRevisions: _pages.map(_editIdentity).toList(),
    preprocessingRevision: preprocessingRevision,
    engine: engine,
    parserVersion: ReceiptParser.version,
  );

  /// Only results whose evidence still matches the current ordered photos may
  /// be shown or handed off, including when a picker cache file changes in place.
  /// This synchronous API reads/hashes evidence on the caller isolate; avoid
  /// repeated lookups in widget builds. Selection uses async validation instead.
  ScanResult? resultForEngine(OcrEngineId id) {
    final engine = _descriptor(id);
    if (_disposed || engine == null || !_inputsPrepared) return null;
    try {
      if (!_sourcesCurrentSync()) return null;
      return _cache.get(
        ScanResultCache.keyForSync(
          originalPaths: _pages.map((page) => page.originalPath).toList(),
          recognitionPaths: _recognitionInputs,
          comparisonPaths: _comparisonInputs,
          photoEditRevisions: _pages.map(_editIdentity).toList(),
          preprocessingRevision: preprocessingRevision,
          engine: engine,
          parserVersion: ReceiptParser.version,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  ScanResult? get selectedResult => resultForEngine(selectedEngineId);

  /// Selection changes presentation only; native inference requires Read/Retry.
  Future<void> selectEngine(OcrEngineId id) async {
    if (_disposed || busy) return;
    final selectionChanged = _selectedEngineId != id;
    _selectedEngineId = id;
    final selection = ++_selectionGeneration;
    final generation = _generation;
    busy = true;
    error = null;
    ocrFailed = false;
    qualityRejected = false;
    _changed();
    try {
      await _engineLoad;
      if (_disposed ||
          selection != _selectionGeneration ||
          generation != _generation) {
        return;
      }
      if (selectionChanged) await adapter.releaseOcrSession();
      if (_disposed ||
          selection != _selectionGeneration ||
          generation != _generation) {
        return;
      }
      final descriptor = _descriptor(id);
      ScanResult? result;
      if (descriptor?.available == true &&
          _inputsPrepared &&
          await _sourcesCurrent()) {
        final key = await _keyFor(descriptor!);
        if (_disposed || generation != _generation) return;
        if (await _sourcesCurrent()) result = _cache.get(key);
      }
      if (_disposed || generation != _generation) return;
      if (result != null) {
        _presentationResults[id] = result;
      } else {
        _presentationResults.remove(id);
      }
      error = descriptor?.available == true
          ? result?.error
          : descriptor?.unavailableReason ?? 'This OCR engine is unavailable.';
      ocrFailed = error != null;
    } catch (failure) {
      if (!_disposed &&
          selection == _selectionGeneration &&
          generation == _generation) {
        error = userMessage(failure);
      }
    } finally {
      _finishOperation();
    }
  }

  void _invalidate({CapturePage? editedPage}) {
    _generation++;
    _cache.clear();
    _presentationResults.clear();
    if (editedPage != null) {
      _editRevisions.update(
        editedPage.id,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    error = null;
    ocrFailed = false;
    qualityRejected = false;
  }

  void _rememberGenerated(CapturePage page, String? path) {
    if (path != null && path != page.originalPath) {
      _generatedPaths[path] = page.originalPath;
    }
  }

  void _bindDerived(CapturePage page, String? path, String originalHash) {
    _rememberGenerated(page, path);
    if (path != null && path != page.originalPath) {
      _derivedOriginalHashes[path] = originalHash;
    }
  }

  Future<void> _cleanupGenerated() async {
    final disposable = Map.of(_generatedPaths)
      ..removeWhere((path, _) => _handedOffPaths.contains(path));
    for (final entry in disposable.entries) {
      try {
        await _images.deleteGenerated([entry.key], originalPath: entry.value);
      } catch (_) {
        // Temporary-cache cleanup never invalidates preserved original evidence.
      }
      _generatedPaths.remove(entry.key);
      _derivedOriginalHashes.remove(entry.key);
    }
  }

  void _finishOperation() {
    busy = false;
    if (_disposed) {
      unawaited(_cleanupGenerated());
    } else {
      _changed();
    }
  }

  Future<void> pick(ImageSource source) async {
    if (_disposed || busy) return;
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
      if (!_disposed) await _append(photos.map((photo) => photo.path));
    } catch (failure) {
      if (_disposed) return;
      error = failure is AppException
          ? failure.message
          : 'Could not add photos. Check camera/photo access in phone settings and try again.';
    } finally {
      _finishOperation();
    }
  }

  /// Input ordering is preserved. Identical original bytes are included once,
  /// even when the picker returns different cache paths for the same photo.
  Future<void> addImages(List<String> paths) async {
    if (_disposed || busy) return;
    busy = true;
    error = null;
    notice = null;
    _changed();
    try {
      await _append(paths);
    } catch (failure) {
      if (!_disposed) error = userMessage(failure);
    } finally {
      _finishOperation();
    }
  }

  Future<void> _append(Iterable<String> paths) async {
    final knownHashes = <String>{};
    for (final page in _pages) {
      final hash = await _images.hash(page.originalPath);
      if (_disposed) return;
      _refreshSource(page, hash);
      knownHashes.add(hash);
    }
    var skipped = 0;
    for (final path in paths) {
      final hash = await _images.hash(path);
      if (_disposed) return;
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
      _bindDerived(page, page.preparedPath, hash);
      if (_disposed) return;
      _sourceHashes[page.id] = hash;
      _preparedSources[page.id] = _preparedIdentity(page, hash);
      _pages.add(page);
      selectedIndex = _pages.length - 1;
      _invalidate();
    }
    if (skipped > 0) {
      notice =
          'Skipped $skipped duplicate ${skipped == 1 ? 'photo' : 'photos'}. Each original page is included once.';
    }
  }

  void selectPage(int index) {
    if (_disposed || busy || index < 0 || index >= _pages.length) return;
    selectedIndex = index;
    _changed();
  }

  void moveSelectedPage(int offset) {
    if (_disposed || busy || _pages.isEmpty) return;
    final next = selectedIndex + offset;
    if (next < 0 || next >= _pages.length) return;
    final page = _pages.removeAt(selectedIndex);
    _pages.insert(next, page);
    selectedIndex = next;
    _invalidate();
    _changed();
  }

  void removeSelectedPage() {
    if (_disposed || busy || _pages.isEmpty) return;
    final removed = _pages.removeAt(selectedIndex);
    // Keep generated media for already handed-off snapshots; unused cache files
    // are collected when this capture session ends.
    _sourceHashes.remove(removed.id);
    _preparedSources.remove(removed.id);
    _editRevisions.remove(removed.id);
    selectedIndex = _pages.isEmpty
        ? 0
        : selectedIndex.clamp(0, _pages.length - 1);
    _invalidate();
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
    if (_disposed || busy || page == null) return;
    busy = true;
    error = null;
    _changed();
    try {
      final originalHash = await _images.hash(page.originalPath);
      if (_disposed) return;
      _refreshSource(page, originalHash);
      final transformed = await _images.transform(
        page.editedPath,
        rotate: rotate,
        crop: crop,
        angleDegrees: angleDegrees,
      );
      _bindDerived(page, transformed, originalHash);
      if (_disposed) return;
      final prepared = await _images.prepareRecognition(
        transformed,
        enhance: page.enhance,
        contrast: page.contrast,
      );
      _bindDerived(page, prepared, originalHash);
      if (_disposed) return;
      final currentOriginalHash = await _images.hash(page.originalPath);
      if (_disposed) return;
      if (currentOriginalHash != originalHash) {
        _refreshSource(page, currentOriginalHash);
        return;
      }
      page.recognitionPath = transformed;
      page.preparedPath = prepared;
      page.useOriginal = false;
      final transformedHash = await _images.hash(transformed);
      if (_disposed) return;
      _preparedSources[page.id] = _preparedIdentity(page, transformedHash);
      _invalidate(editedPage: page);
    } catch (failure) {
      if (!_disposed) error = userMessage(failure);
    } finally {
      _finishOperation();
    }
  }

  void resetEdits() {
    if (_disposed || busy || selectedPage == null) return;
    selectedPage!.recognitionPath = null;
    selectedPage!.preparedPath = null;
    _preparedSources.remove(selectedPage!.id);
    _invalidate(editedPage: selectedPage);
    _changed();
  }

  void setEnhanceForOcr(bool enabled) {
    if (_disposed || busy || enhanceForOcr == enabled) return;
    _defaultEnhance = enabled;
    for (final page in _pages) {
      page.enhance = enabled;
      page.preparedPath = null;
    }
    _preparedSources.clear();
    _invalidate();
    _changed();
  }

  /// Locks selection, additions, removal and recognition while the editor is
  /// open. The page itself is unchanged until a successful Apply edits result.
  bool beginPhotoEdit() {
    if (busy || _disposed || selectedPage == null) return false;
    final page = selectedPage!;
    try {
      final originalHash = _hashSync(page.originalPath);
      _refreshSource(page, originalHash);
      _editorOriginalHash = originalHash;
      _editorGeometryPath = page.editedPath;
      _editorGeometryHash = page.editedPath == page.originalPath
          ? originalHash
          : _hashSync(page.editedPath);
    } catch (failure) {
      error = userMessage(failure);
      _changed();
      return false;
    }
    _editorOpen = true;
    busy = true;
    _changed();
    return true;
  }

  void finishPhotoEdit(CapturePage page, ReceiptPhotoEdits? edits) {
    if (!_editorOpen) return;
    _editorOpen = false;
    if (edits != null) {
      _rememberGenerated(page, edits.editedPath);
      _rememberGenerated(page, edits.enhancedPath);
    }
    if (edits != null && !_disposed && _pages.contains(page)) {
      page.enhance = edits.enhance;
      page.contrast = edits.contrast;
      try {
        final originalHash = _hashSync(page.originalPath);
        if (originalHash != _editorOriginalHash ||
            _editorGeometryPath == null ||
            _hashSync(_editorGeometryPath!) != _editorGeometryHash) {
          _resetDerived(page, originalHash);
        } else {
          page.recognitionPath = edits.editedPath;
          page.preparedPath = edits.enhancedPath;
          page.useOriginal = edits.useOriginal;
          _bindDerived(page, edits.editedPath, originalHash);
          _bindDerived(page, edits.enhancedPath, originalHash);
          _preparedSources[page.id] = _preparedIdentity(
            page,
            page.editedPath == page.originalPath
                ? originalHash
                : _hashSync(page.editedPath),
          );
          _invalidate(editedPage: page);
        }
      } catch (failure) {
        _resetDerived(page, null);
        error = userMessage(failure);
      }
    }
    _editorOriginalHash = null;
    _editorGeometryPath = null;
    _editorGeometryHash = null;
    _finishOperation();
  }

  String _preparedIdentity(CapturePage page, String sourceHash) => jsonEncode([
    _sourceHashes[page.id],
    sourceHash,
    page.enhance,
    page.contrast,
    preprocessingRevision,
  ]);

  void _refreshSource(CapturePage page, String hash) {
    final previous = _sourceHashes[page.id];
    if ((previous != null && previous != hash) || !_derivedMatch(page, hash)) {
      _resetDerived(page, hash);
    }
    _sourceHashes[page.id] = hash;
    page.originalHash = hash;
  }

  void _resetDerived(CapturePage page, String? currentHash) {
    // Crop/rotation are materialized, so stale geometry must be reapplied.
    // Contrast/enhancement remain the owner's selected settings.
    page.recognitionPath = null;
    page.preparedPath = null;
    page.originalPreparedPath = null;
    _preparedSources.remove(page.id);
    if (currentHash == null) {
      _sourceHashes.remove(page.id);
    } else {
      _sourceHashes[page.id] = currentHash;
    }
    page.originalHash = currentHash;
    _invalidate(editedPage: page);
    notice =
        'A source photo changed. Check the photo and reapply any crop or rotation edits before reading it.';
  }

  bool _derivedMatch(CapturePage page, String originalHash) =>
      [page.recognitionPath, page.preparedPath, page.originalPreparedPath]
          .whereType<String>()
          .where((path) => path != page.originalPath)
          .every((path) => _derivedOriginalHashes[path] == originalHash);

  static String _hashSync(String path) =>
      sha256.convert(File(path).readAsBytesSync()).toString();

  bool _sourcesCurrentSync() {
    final hashes = <String, String>{};
    String hash(String path) => hashes.putIfAbsent(path, () => _hashSync(path));
    return _pages.every((page) {
      final original = hash(page.originalPath);
      return _sourceHashes[page.id] == original &&
          _derivedMatch(page, original) &&
          (page.useOriginal ||
              _preparedSources[page.id] ==
                  _preparedIdentity(page, hash(page.editedPath)));
    });
  }

  /// Revalidates every page together, including pages whose preparation finished
  /// earlier. Each copy remains bound to the original/source used to produce it.
  Future<bool> _sourcesCurrent() async {
    final hashes = <String, Future<String>>{};
    Future<String> hash(String path) =>
        hashes.putIfAbsent(path, () => _images.hash(path));
    for (final page in _pages) {
      final original = await hash(page.originalPath);
      if (_disposed) return false;
      if (_sourceHashes[page.id] != original ||
          !_derivedMatch(page, original)) {
        _resetDerived(page, original);
        return false;
      }
      if (!page.useOriginal && page.preparedPath != null) {
        final source = await hash(page.editedPath);
        if (_disposed) return false;
        if (_preparedSources[page.id] != _preparedIdentity(page, source)) {
          page.preparedPath = null;
          _preparedSources.remove(page.id);
          _invalidate(editedPage: page);
          notice =
              'An edited photo changed. Check the photo and read it again.';
          return false;
        }
      }
    }
    return !_disposed;
  }

  Future<void> recognizeSelected() async {
    await _recognize();
  }

  /// Compatibility for the current Review navigation. New UI uses a completed
  /// selected result followed by an explicit private snapshot handoff.
  Future<ReceiptDraft?> recognize({bool allowLowQuality = false}) async {
    final result = await _recognize(allowLowQuality: allowLowQuality);
    if (result?.draft == null || _disposed) return null;
    try {
      return await selectedDraftSnapshotAsync();
    } on StateError {
      return null;
    }
  }

  Future<ScanResult?> _recognize({bool allowLowQuality = false}) async {
    if (_disposed || busy || _pages.isEmpty) return null;
    busy = true;
    error = null;
    ocrFailed = false;
    qualityRejected = false;
    _changed();
    String? key;
    OcrEngineDescriptor? engine;
    var generation = _generation;
    final watch = Stopwatch()..start();
    try {
      await _engineLoad;
      if (_disposed) return null;
      engine = _descriptor(selectedEngineId);
      if (engine == null || !engine.available) {
        throw AppException(
          engine?.unavailableReason ?? 'This OCR engine is unavailable.',
        );
      }
      for (var index = 0; index < _pages.length; index++) {
        final page = _pages[index];
        final originalHash = await _images.hash(page.originalPath);
        if (_disposed) return null;
        _refreshSource(page, originalHash);
        generation = _generation;
        final quality = await _images.inspectQuality(
          page.useOriginal ? page.originalPath : page.editedPath,
        );
        if (_disposed) return null;
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
          _bindDerived(page, page.originalPreparedPath, originalHash);
        } else {
          final sourceHash = page.editedPath == page.originalPath
              ? originalHash
              : await _images.hash(page.editedPath);
          final identity = _preparedIdentity(page, sourceHash);
          if (_preparedSources[page.id] != null &&
              _preparedSources[page.id] != identity) {
            page.preparedPath = null;
            _invalidate(editedPage: page);
            generation = _generation;
          }
          page.preparedPath ??= await _images.prepareRecognition(
            page.editedPath,
            enhance: page.enhance,
            contrast: page.contrast,
          );
          _bindDerived(page, page.preparedPath, originalHash);
          _preparedSources[page.id] = identity;
        }
        if (_disposed) return null;
        final currentOriginalHash = await _images.hash(page.originalPath);
        if (_disposed) return null;
        if (currentOriginalHash != originalHash) {
          _resetDerived(page, currentOriginalHash);
          return null;
        }
      }
      if (_disposed) return null;
      if (!await _sourcesCurrent()) return null;
      key = await _keyFor(engine);
      if (_disposed || generation != _generation) return null;
      if (!await _runIsCurrent(generation, engine, key)) return null;
      final cached = _cache.get(key);
      if (cached?.draft != null) {
        _presentationResults[engine.id] = cached!;
        return cached;
      }
      final originals = _pages.map((page) => page.originalPath).toList();
      final recognition = _recognitionInputs;
      final comparison = _comparisonInputs;
      final draft = await adapter.processReceiptImages(
        originals,
        recognitionImagePaths: recognition,
        comparisonImagePaths: comparison,
        engineId: engine.id,
        preprocessingRevision: preprocessingRevision,
      );
      if (!await _runIsCurrent(generation, engine, key)) return null;
      final result = ScanResult(
        key: key,
        engineId: engine.id,
        draft: draft,
        elapsedMs: watch.elapsedMilliseconds,
      );
      _cache.put(result);
      _presentationResults[engine.id] = result;
      return result;
    } catch (failure) {
      if (_disposed || generation != _generation) return null;
      if (key != null &&
          engine != null &&
          !await _runIsCurrent(generation, engine, key)) {
        return null;
      }
      if (_disposed) return null;
      error = userMessage(failure);
      ocrFailed = true;
      if (key != null && engine != null) {
        final result = ScanResult(
          key: key,
          engineId: engine.id,
          error: error,
          elapsedMs: watch.elapsedMilliseconds,
        );
        _cache.put(result);
        _presentationResults[engine.id] = result;
      }
      return null;
    } finally {
      watch.stop();
      _finishOperation();
    }
  }

  Future<bool> _runIsCurrent(
    int generation,
    OcrEngineDescriptor engine,
    String key,
  ) async {
    if (_disposed ||
        generation != _generation ||
        selectedEngineId != engine.id) {
      return false;
    }
    try {
      if (!await _sourcesCurrent()) return false;
      final current = await _keyFor(engine);
      return !_disposed &&
          generation == _generation &&
          current == key &&
          await _sourcesCurrent() &&
          generation == _generation;
    } catch (_) {
      return false;
    }
  }

  ReceiptDraft selectedDraftSnapshot() {
    final draft = selectedResult?.draft;
    if (draft == null) {
      throw StateError('Read the current photos before using an OCR result.');
    }
    return _handoffDraft(draft);
  }

  /// Fresh async authority for explicit Review/Save actions. The published
  /// presentation key is only a candidate: actual role bytes and source binding
  /// must still match the private cache. A changing input, selection or disposed
  /// state fails with StateError; validation never performs OCR or preprocessing.
  /// Callers serialize their action while awaiting and show a re-read notice on
  /// failure. The synchronous API remains available for existing integrations.
  Future<ReceiptDraft> selectedDraftSnapshotAsync() async {
    final generation = _generation;
    final selection = _selectionGeneration;
    final engine = _descriptor(selectedEngineId);
    final candidate = _presentationResults[selectedEngineId];
    if (_disposed ||
        busy ||
        engine == null ||
        !_inputsPrepared ||
        candidate == null) {
      throw StateError('Read the current photos before using an OCR result.');
    }
    if (!await _runIsCurrent(generation, engine, candidate.key) ||
        _disposed ||
        generation != _generation ||
        selection != _selectionGeneration ||
        selectedEngineId != engine.id) {
      throw StateError(
        'The receipt photos or selected result changed. Read them again.',
      );
    }
    final draft = _cache.get(candidate.key)?.draft;
    if (draft == null) {
      throw StateError('Read the current photos before using an OCR result.');
    }
    return _handoffDraft(draft);
  }

  ReceiptDraft _handoffDraft(ReceiptDraft draft) {
    // These generated images belong to the receiving Review/Save workflow now.
    // Reprocessing or closing this capture must not remove its OCR evidence.
    _handedOffPaths.addAll(_recognitionInputs);
    _handedOffPaths.addAll(_comparisonInputs);
    if (draft.recognitionImagePath != null) {
      _handedOffPaths.add(draft.recognitionImagePath!);
    }
    for (final page in draft.ocrPages) {
      if (page.recognitionImagePath != null) {
        _handedOffPaths.add(page.recognitionImagePath!);
      }
      if (page.comparisonImagePath != null) {
        _handedOffPaths.add(page.comparisonImagePath!);
      }
    }
    return draft;
  }

  ReceiptDraft photosOnlyDraftSnapshot() {
    if (_disposed || _pages.isEmpty) {
      throw StateError('Add receipt photos first.');
    }
    return ReceiptDraft(
      imagePath: _pages.first.originalPath,
      imagePaths: _pages.map((page) => page.originalPath).toList(),
      warnings: ['Enter and confirm the information from every original page.'],
    );
  }

  ReceiptDraft manualDraft() => photosOnlyDraftSnapshot();
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _selectionGeneration++;
    _cache.clear();
    _presentationResults.clear();
    unawaited(_releaseSession());
    if (!busy) unawaited(_cleanupGenerated());
    super.dispose();
  }

  Future<void> _releaseSession() async {
    try {
      await adapter.releaseOcrSession();
    } catch (_) {
      // Native disposal can fail after the platform has already torn down its
      // channel. A closed ChangeNotifier cannot present or publish that error.
    }
  }
}
