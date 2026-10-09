import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/features/receipt_scan/state/capture_state.dart';

class CaptureAdapter extends MockReseeboDataAdapter {
  List<String>? originals;
  List<String>? adjusted;

  @override
  Future<ReceiptDraft> processReceiptImages(
    List<String> localImagePaths, {
    List<String>? recognitionImagePaths,
  }) async {
    originals = List.of(localImagePaths);
    adjusted = List.of(recognitionImagePaths!);
    return ReceiptDraft(imagePath: originals!.first, imagePaths: originals);
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
    await directory.delete(recursive: true);
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
}
