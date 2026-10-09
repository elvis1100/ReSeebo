import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/features/receipt_scan/state/capture_state.dart';
import 'package:reseebo_app/features/receipt_scan/state/receipt_photo_editor_state.dart';

class CaptureAdapter extends MockReseeboDataAdapter {
  List<String>? originals;
  List<String>? adjusted;

  @override
  Future<ReceiptDraft> processReceiptImages(
    List<String> localImagePaths, {
    List<String>? recognitionImagePaths,
    List<String>? comparisonImagePaths,
  }) async {
    originals = List.of(localImagePaths);
    adjusted = List.of(recognitionImagePaths!);
    return ReceiptDraft(imagePath: originals!.first, imagePaths: originals);
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
  }) async {
    entered.complete();
    await release.future;
    return super.processReceiptImages(
      localImagePaths,
      recognitionImagePaths: recognitionImagePaths,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late CaptureAdapter adapter;
  late CaptureState state;

  Future<String> photo(String name, {bool blank = false}) async {
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
            color: img.ColorRgb8(150, 150, 150),
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
    if (await directory.exists()) {
      try {
        await directory.delete(recursive: true);
      } catch (_) {}
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
}
