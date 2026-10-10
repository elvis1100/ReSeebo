import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/models/ocr_engine.dart';
import 'package:reseebo_app/features/receipt_scan/state/capture_state.dart';
import 'package:reseebo_app/features/receipt_scan/state/receipt_photo_editor_state.dart';
import 'package:reseebo_app/features/receipt_scan/services/local_receipt_image_service.dart';

class CaptureAdapter extends MockReseeboDataAdapter {
  List<String>? originals;
  List<String>? adjusted;
  final calls = <OcrEngineId>[];
  final failures = <OcrEngineId>{};
  int sessionReleases = 0;
  int adapterCloses = 0;

  @override
  Future<List<OcrEngineDescriptor>> getOcrEngines() async => [
    for (final id in OcrEngineId.values)
      OcrEngineDescriptor(
        id: id,
        label: id.wireId,
        modelVersion: 'test-model',
        runtimeVersion: 'test-runtime',
        available: true,
      ),
  ];

  @override
  Future<void> releaseOcrSession() async {
    sessionReleases++;
  }

  @override
  Future<void> close() async {
    adapterCloses++;
  }

  @override
  Future<ReceiptDraft> processReceiptImages(
    List<String> localImagePaths, {
    List<String>? recognitionImagePaths,
    List<String>? comparisonImagePaths,
    OcrEngineId engineId = OcrEngineId.mlKit,
    String preprocessingRevision = '1',
  }) async {
    calls.add(engineId);
    if (failures.contains(engineId)) {
      throw const FormatException('engine failed');
    }
    originals = List.of(localImagePaths);
    adjusted = List.of(recognitionImagePaths!);
    return ReceiptDraft(
      imagePath: originals!.first,
      imagePaths: originals,
      recognitionImagePath: adjusted!.first,
      rawText: engineId.wireId,
      lines: [ParsedLineItem(description: 'Original item', quantity: 2)],
    );
  }
}

class BlockingCaptureAdapter extends CaptureAdapter {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<ReceiptDraft> processReceiptImages(
    List<String> localImagePaths, {
    List<String>? recognitionImagePaths,
    List<String>? comparisonImagePaths,
    OcrEngineId engineId = OcrEngineId.mlKit,
    String preprocessingRevision = '1',
  }) async {
    entered.complete();
    await release.future;
    return super.processReceiptImages(
      localImagePaths,
      recognitionImagePaths: recognitionImagePaths,
      comparisonImagePaths: comparisonImagePaths,
      engineId: engineId,
      preprocessingRevision: preprocessingRevision,
    );
  }
}

class CancelingPicker extends ImagePicker {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    entered.complete();
    await release.future;
    return [];
  }
}

class BlockingReleaseAdapter extends CaptureAdapter {
  final releaseEntered = Completer<void>();
  final releaseFinished = Completer<void>();
  bool failRelease = false;

  @override
  Future<void> releaseOcrSession() async {
    sessionReleases++;
    if (sessionReleases != 1) return;
    releaseEntered.complete();
    await releaseFinished.future;
    if (failRelease) throw const FormatException('native release failed');
  }
}

class BlockingImageService extends LocalReceiptImageService {
  final prepareEntered = Completer<void>();
  final prepareReleased = Completer<void>();
  final cleaned = Completer<void>();
  String? generated;

  @override
  Future<String> prepareRecognition(
    String path, {
    bool enhance = true,
    double contrast = 1,
  }) async {
    if (!prepareEntered.isCompleted) {
      prepareEntered.complete();
      await prepareReleased.future;
    }
    return generated = await super.prepareRecognition(
      path,
      enhance: enhance,
      contrast: contrast,
    );
  }

  @override
  Future<void> deleteGenerated(
    Iterable<String?> paths, {
    required String originalPath,
  }) async {
    await super.deleteGenerated(paths, originalPath: originalPath);
    if (!cleaned.isCompleted) cleaned.complete();
  }
}

class PagePreparationBarrier extends LocalReceiptImageService {
  String? blockedPath;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<String> prepareRecognition(
    String path, {
    bool enhance = true,
    double contrast = 1,
  }) async {
    if (path == blockedPath && !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return super.prepareRecognition(path, enhance: enhance, contrast: contrast);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late CaptureAdapter adapter;
  late CaptureState state;

  Future<String> photo(String name, {bool blank = false, int ink = 150}) async {
    final image = img.Image(width: 400, height: 600);
    img.fill(image, color: img.ColorRgb8(245, 245, 245));
    if (!blank) {
      for (var y = 40; y < 560; y += 24) {
        for (var x = 30; x < 370; x += 16) {
          img.fillRect(
            image,
            x1: x,
            y1: y,
            x2: x + 8,
            y2: y + 10,
            color: img.ColorRgb8(ink, ink, ink),
          );
        }
      }
    }
    final file = File('${directory.path}/$name.png');
    await file.writeAsBytes(img.encodePng(image));
    return file.path;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reseebo-capture-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => directory.path,
        );
    adapter = CaptureAdapter();
    state = CaptureState(adapter: adapter);
  });
  tearDown(() async {
    state.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    // dispose deliberately cleans generated files asynchronously. On Windows,
    // recursive test cleanup can enumerate a child just before capture removes
    // it. Retry only that race; other filesystem failures remain test failures.
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await directory.delete(recursive: true);
        break;
      } on PathNotFoundException {
        if (!await directory.exists()) break;
        if (attempt == 2) rethrow;
      }
    }
  });

  test(
    'recognition prepares a separate image and retains ordered originals',
    () async {
      final original = await photo('receipt');
      await state.addImages([original]);
      final draft = await state.recognize();
      expect(draft, isNotNull);
      expect(adapter.originals, [original]);
      expect(adapter.adjusted!.single, isNot(original));
      final prepared = img.decodeImage(
        await File(adapter.adjusted!.single).readAsBytes(),
      )!;
      expect(prepared.getPixel(32, 43).r, lessThan(100));
      expect(state.pages.single.originalPath, original);
    },
  );

  test(
    'poor input stops before OCR while manual draft retains the photo',
    () async {
      final original = await photo('blank', blank: true);
      await state.addImages([original]);
      expect(await state.recognize(), isNull);
      expect(adapter.originals, isNull);
      expect(state.error, isNotNull);
      expect(state.manualDraft().imagePaths, [original]);
      expect(state.busy, isFalse);
    },
  );

  test(
    'owner can continue after quality triage without losing the original',
    () async {
      final original = await photo('override', blank: true);
      await state.addImages([original]);
      expect(await state.recognize(), isNull);
      expect(state.qualityRejected, isTrue);
      final draft = await state.recognize(allowLowQuality: true);
      expect(draft!.imagePaths, [original]);
      expect(adapter.adjusted!.single, isNot(original));
      expect(state.qualityRejected, isFalse);
    },
  );

  test('disabling enhancement rebuilds OCR copy from edited photo', () async {
    final original = await photo('contrast');
    await state.addImages([original]);
    await state.recognize();
    final first = adapter.adjusted!.single;
    state.setEnhanceForOcr(false);
    await state.recognize();
    final second = adapter.adjusted!.single;
    final image = img.decodeImage(await File(second).readAsBytes())!;
    expect(second, isNot(first));
    expect(image.getPixel(32, 43).r, greaterThan(120));
    expect(adapter.originals, [original]);
  });
  test(
    'staged crop and contrast use the exact enhanced preview for OCR; original choice bypasses edits',
    () async {
      final original = await photo('editor');
      final bytes = await File(original).readAsBytes();
      await state.addImages([original]);
      final page = state.pages.single;
      expect(state.beginPhotoEdit(), isTrue);
      final editor = ReceiptPhotoEditorState(page: page);
      await editor.initialize();
      await editor.transform(crop: [.1, .1, .9, .9]);
      await editor.setContrast(1.5);
      expect(page.recognitionPath, isNull);
      final applied = editor.apply()!;
      state.finishPhotoEdit(page, applied);
      editor.dispose();
      await state.recognize();
      expect(adapter.adjusted, [applied.enhancedPath]);
      final cropped = img.decodeImage(
        await File(adapter.adjusted!.single).readAsBytes(),
      )!;
      expect(cropped.width, 320);
      expect(cropped.height, 480);

      expect(state.beginPhotoEdit(), isTrue);
      final originalEditor = ReceiptPhotoEditorState(page: page);
      await originalEditor.initialize();
      originalEditor.selectOriginal(true);
      state.finishPhotoEdit(page, originalEditor.apply());
      originalEditor.dispose();
      await state.recognize();
      expect(adapter.adjusted!.single, isNot(applied.enhancedPath));
      final unedited = img.decodeImage(
        await File(adapter.adjusted!.single).readAsBytes(),
      )!;
      expect(unedited.width, 400);
      expect(unedited.height, 600);
      expect(unedited.getPixel(32, 43).r, greaterThan(120));
      expect(adapter.originals, [original]);
      expect(await File(original).readAsBytes(), bytes);
    },
  );

  test(
    'canceling staged edits keeps selected settings and original evidence intact',
    () async {
      final original = await photo('cancel-editor');
      final bytes = await File(original).readAsBytes();
      await state.addImages([original]);
      final page = state.pages.single;
      final preview = page.preparedPath;
      expect(state.beginPhotoEdit(), isTrue);
      final editor = ReceiptPhotoEditorState(page: page);
      await editor.transform(rotate: true);
      editor.selectOriginal(true);
      state.finishPhotoEdit(page, null);
      editor.dispose();
      expect(page.preparedPath, preview);
      expect(page.recognitionPath, isNull);
      expect(page.useOriginal, isFalse);
      expect(state.busy, isFalse);
      expect(await File(preview!).exists(), isTrue);
      expect(await File(original).readAsBytes(), bytes);
    },
  );

  test(
    'reading locks page selection, removal, edits, additions and duplicate reads',
    () async {
      state.dispose();
      final blocking = BlockingCaptureAdapter();
      adapter = blocking;
      state = CaptureState(adapter: blocking);
      final original = await photo('busy-reading');
      await state.addImages([original]);
      final pending = state.recognize();
      await blocking.entered.future;
      expect(state.busy, isTrue);
      state.removeSelectedPage();
      state.selectPage(1);
      state.moveSelectedPage(1);
      await state.transform(rotate: true);
      await state.addImages([original]);
      state.setEnhanceForOcr(false);
      expect(state.beginPhotoEdit(), isFalse);
      await state.selectEngine(OcrEngineId.ppOcrV6Medium);
      expect(state.selectedEngineId, OcrEngineId.mlKit);
      expect(await state.recognize(), isNull);
      expect(state.pages.single.originalPath, original);
      expect(state.pages.single.recognitionPath, isNull);
      expect(state.selectedIndex, 0);
      expect(state.enhanceForOcr, isTrue);
      blocking.release.complete();
      expect(await pending, isNotNull);
      expect(state.busy, isFalse);
    },
  );

  test('switch_restores_result_without_inference', () async {
    await state.addImages([await photo('switch')]);
    await state.recognizeSelected();
    await state.selectEngine(OcrEngineId.ppOcrV5Mobile);
    expect(state.selectedResult, isNull);
    expect(adapter.calls, [OcrEngineId.mlKit]);
    await state.recognizeSelected();
    expect(state.selectedResult!.draft!.rawText, 'ppocr_v5_mobile');
    await state.selectEngine(OcrEngineId.mlKit);
    expect(state.selectedResult!.draft!.rawText, 'mlkit');
    expect(adapter.calls, [OcrEngineId.mlKit, OcrEngineId.ppOcrV5Mobile]);
    await state.recognizeSelected();
    expect(adapter.calls.length, 2);
    expect(state.busy, isFalse);
  });

  test(
    'failed_engine_does_not_erase_other_result and retry restores controls',
    () async {
      await state.addImages([await photo('failure')]);
      await state.recognizeSelected();
      adapter.failures.add(OcrEngineId.ppOcrV6Medium);
      await state.selectEngine(OcrEngineId.ppOcrV6Medium);
      await state.recognizeSelected();
      expect(state.selectedResult!.error, isNotNull);
      expect(state.selectedResult!.draft, isNull);
      expect(state.busy, isFalse);
      await state.selectEngine(OcrEngineId.mlKit);
      expect(state.selectedResult!.draft!.rawText, 'mlkit');
      expect(state.error, isNull);
      await state.selectEngine(OcrEngineId.ppOcrV6Medium);
      adapter.failures.clear();
      await state.recognizeSelected();
      expect(state.selectedResult!.draft!.rawText, 'ppocr_v6_medium');
      expect(state.error, isNull);
      expect(state.busy, isFalse);
    },
  );

  test(
    'review_snapshot_does_not_mutate_cache or delete handed-off evidence',
    () async {
      final original = await photo('snapshot');
      await state.addImages([original]);
      await state.recognizeSelected();
      final review = state.selectedDraftSnapshot();
      review.rawText = 'owner changed';
      review.lines.single.description = 'Owner item';
      review.lines.single.quantity = 9;
      state.selectedResult!.draft!.lines.clear();
      final again = state.selectedDraftSnapshot();
      expect(again.rawText, 'mlkit');
      expect(again.lines.single.description, 'Original item');
      expect(again.lines.single.quantity, 2);
      final evidence = again.recognitionImagePath!;
      state.setEnhanceForOcr(false);
      await state.recognizeSelected();
      state.removeSelectedPage();
      expect(await File(evidence).exists(), isTrue);
      expect(await File(original).exists(), isTrue);
    },
  );

  test(
    'late_result_after_invalidation_is_ignored when source bytes mutate',
    () async {
      state.dispose();
      final blocking = BlockingCaptureAdapter();
      adapter = blocking;
      state = CaptureState(adapter: blocking);
      final original = await photo('late');
      await state.addImages([original]);
      final pending = state.recognizeSelected();
      await blocking.entered.future;
      await photo('late', ink: 75);
      blocking.release.complete();
      await pending;
      expect(state.selectedResult, isNull);
      expect(state.busy, isFalse);
      expect(() => state.selectedDraftSnapshot(), throwsStateError);
    },
  );

  test(
    'dispose_never_notifies or closes shared adapter after delayed inference',
    () async {
      state.dispose();
      final blocking = BlockingCaptureAdapter();
      final closed = CaptureState(adapter: blocking);
      await closed.addImages([await photo('dispose')]);
      var notifications = 0;
      closed.addListener(() {
        notifications++;
      });
      final pending = closed.recognizeSelected();
      await blocking.entered.future;
      closed.dispose();
      final before = notifications;
      blocking.release.complete();
      await pending;
      await Future<void>.delayed(Duration.zero);
      expect(notifications, before);
      expect(closed.selectedResult, isNull);
      expect(blocking.sessionReleases, 1);
      expect(blocking.adapterCloses, 0);
      // Replace the disposed test fixture for tearDown.
      state = CaptureState(adapter: adapter);
    },
  );

  test(
    'original mutation refreshes generated inputs despite cached originalHash',
    () async {
      final original = await photo('mutate');
      await state.addImages([original]);
      await state.recognizeSelected();
      final oldPrepared = adapter.adjusted!.single;
      final oldHash = state.pages.single.originalHash;
      await photo('mutate', ink: 65);
      expect(state.selectedResult, isNull);
      expect(() => state.selectedDraftSnapshot(), throwsStateError);
      await state.recognizeSelected();
      expect(adapter.calls.length, 2);
      expect(adapter.adjusted!.single, isNot(oldPrepared));
      expect(state.pages.single.originalHash, isNot(oldHash));
      expect(state.selectedResult, isNotNull);
    },
  );

  test(
    'order and applied edits invalidate every engine; canceled edit does not',
    () async {
      await state.addImages([
        await photo('first'),
        await photo('second', ink: 90),
      ]);
      await state.recognizeSelected();
      expect(state.beginPhotoEdit(), isTrue);
      state.finishPhotoEdit(state.selectedPage!, null);
      expect(state.selectedResult, isNotNull);
      state.moveSelectedPage(-1);
      expect(state.selectedResult, isNull);
      await state.recognizeSelected();
      expect(adapter.calls.length, 2);
      state.resetEdits();
      expect(state.selectedResult, isNull);
      expect(state.busy, isFalse);
    },
  );

  test(
    'canceled picker preserves selected result and restores controls',
    () async {
      state.dispose();
      final picker = CancelingPicker();
      state = CaptureState(adapter: adapter, picker: picker);
      await state.addImages([await photo('picker')]);
      await state.recognizeSelected();
      final pending = state.pick(ImageSource.gallery);
      await picker.entered.future;
      expect(state.busy, isTrue);
      picker.release.complete();
      await pending;
      expect(state.busy, isFalse);
      expect(state.selectedResult!.draft!.rawText, 'mlkit');
      expect(adapter.calls.length, 1);
    },
  );

  test('photos-only handoff retains originals without OCR', () async {
    final original = await photo('photos-only');
    await state.addImages([original]);
    final draft = state.photosOnlyDraftSnapshot();
    expect(draft.imagePaths, [original]);
    expect(draft.lines, isEmpty);
    expect(draft.ocrRun, isNull);
    expect(adapter.calls, isEmpty);
    expect(() => state.selectedDraftSnapshot(), throwsStateError);
  });

  test(
    'actual engine switch releases native session even for cached results',
    () async {
      await state.addImages([await photo('switch-release')]);
      await state.recognizeSelected();
      await state.selectEngine(OcrEngineId.ppOcrV5Mobile);
      expect(adapter.sessionReleases, 1);
      expect(adapter.adapterCloses, 0);
      await state.recognizeSelected();
      await state.selectEngine(OcrEngineId.mlKit);
      expect(adapter.sessionReleases, 2);
      expect(state.selectedResult!.draft!.rawText, 'mlkit');
      expect(adapter.calls.length, 2);
      await state.selectEngine(OcrEngineId.mlKit);
      expect(adapter.sessionReleases, 2);
    },
  );

  test(
    'native release failure restores controls and retains other result',
    () async {
      state.dispose();
      final releasing = BlockingReleaseAdapter()..failRelease = true;
      adapter = releasing;
      state = CaptureState(adapter: releasing);
      await state.addImages([await photo('release-failure')]);
      await state.recognizeSelected();
      final selection = state.selectEngine(OcrEngineId.ppOcrV5Mobile);
      await releasing.releaseEntered.future.timeout(const Duration(seconds: 2));
      expect(state.busy, isTrue);
      expect(await state.recognize(), isNull);
      state.removeSelectedPage();
      expect(state.pages.length, 1);
      releasing.releaseFinished.complete();
      await selection;
      expect(state.error, isNotNull);
      expect(state.busy, isFalse);
      await state.selectEngine(OcrEngineId.mlKit);
      expect(state.selectedResult!.draft!.rawText, 'mlkit');
      expect(state.error, isNull);
      expect(releasing.adapterCloses, 0);
    },
  );

  test('dispose during engine release never publishes or notifies', () async {
    final releasing = BlockingReleaseAdapter();
    final closed = CaptureState(adapter: releasing);
    await closed.addImages([await photo('release-dispose')]);
    var notifications = 0;
    closed.addListener(() {
      notifications++;
    });
    final selection = closed.selectEngine(OcrEngineId.ppOcrV5Mobile);
    await releasing.releaseEntered.future.timeout(const Duration(seconds: 2));
    closed.dispose();
    final before = notifications;
    releasing.releaseFinished.complete();
    await selection;
    expect(notifications, before);
    expect(closed.selectedResult, isNull);
    expect(closed.busy, isFalse);
    expect(releasing.adapterCloses, 0);
  });

  test(
    'late prepared files are cleaned after disposal without touching original',
    () async {
      final images = BlockingImageService();
      final original = await photo('late-prepare');
      final closed = CaptureState(
        adapter: adapter,
        imageService: images,
        initialImagePath: original,
      );
      final read = closed.recognizeSelected();
      await images.prepareEntered.future;
      closed.dispose();
      images.prepareReleased.complete();
      await read;
      await images.cleaned.future;
      expect(await File(images.generated!).exists(), isFalse);
      expect(await File(original).exists(), isTrue);
      expect(adapter.calls, isEmpty);
    },
  );

  test(
    'earlier page replacement during later preparation discards mixed evidence and next read rebuilds',
    () async {
      state.dispose();
      final images = PagePreparationBarrier();
      state = CaptureState(adapter: adapter, imageService: images);
      final first = await photo('barrier-first');
      final second = await photo('barrier-second', ink: 90);
      await state.addImages([first, second]);
      state.setEnhanceForOcr(false);
      images.blockedPath = second;
      final read = state.recognizeSelected();
      await images.entered.future;
      await photo('barrier-first', ink: 65);
      images.release.complete();
      await read;
      expect(adapter.calls, isEmpty);
      expect(state.selectedResult, isNull);
      expect(() => state.selectedDraftSnapshot(), throwsStateError);
      expect(state.busy, isFalse);
      expect(state.notice, contains('reapply'));
      await state.recognizeSelected();
      expect(adapter.calls.length, 1);
      expect(adapter.originals, [first, second]);
      final rebuilt = img.decodeImage(
        await File(adapter.adjusted!.first).readAsBytes(),
      )!;
      expect(rebuilt.width, 400);
      expect(rebuilt.height, 600);
      expect(rebuilt.getPixel(32, 43).r, lessThan(100));
      expect(state.selectedDraftSnapshot().imagePaths, [first, second]);
    },
  );

  for (final useEditor in [false, true]) {
    test(
      'initial image geometry ${useEditor ? 'editor' : 'transform'} establishes original identity before first read',
      () async {
        state.dispose();
        final original = await photo('initial-geometry');
        state = CaptureState(adapter: adapter, initialImagePath: original);
        final page = state.pages.single;
        if (useEditor) {
          expect(state.beginPhotoEdit(), isTrue);
          final editor = ReceiptPhotoEditorState(page: page);
          await editor.initialize();
          await editor.transform(rotate: true);
          await editor.transform(crop: [.1, .1, .9, .9]);
          await editor.setEnhance(false);
          await editor.setContrast(1.4);
          state.finishPhotoEdit(page, editor.apply());
          editor.dispose();
        } else {
          await state.transform(rotate: true);
          await state.transform(crop: [.1, .1, .9, .9]);
          state.setEnhanceForOcr(false);
          page.contrast = 1.4;
        }
        expect(page.recognitionPath, isNotNull);
        await photo('initial-geometry', ink: 60);
        await state.recognizeSelected();
        expect(page.recognitionPath, isNull);
        expect(page.enhance, isFalse);
        expect(page.contrast, 1.4);
        expect(state.notice, contains('reapply'));
        expect(adapter.calls.length, 1);
        final rebuilt = img.decodeImage(
          await File(adapter.adjusted!.single).readAsBytes(),
        )!;
        expect(rebuilt.width, 400);
        expect(rebuilt.height, 600);
        expect(rebuilt.getPixel(32, 43).r, lessThan(60));
        expect(state.busy, isFalse);
      },
    );
  }
}
