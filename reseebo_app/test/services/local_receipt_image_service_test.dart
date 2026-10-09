import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reseebo_app/core/errors/app_exception.dart';
import 'package:reseebo_app/features/receipt_scan/services/local_receipt_image_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final service = LocalReceiptImageService();

  img.Image receipt({bool faded = false}) {
    final image = img.Image(width: 600, height: 800);
    img.fill(image, color: img.ColorRgb8(245, 245, 245));
    for (var y = 50; y < 750; y += 35) {
      for (var x = 45; x < 540; x += 18) {
        img.fillRect(
          image,
          x1: x,
          y1: y,
          x2: x + 10,
          y2: y + 12,
          color: faded
              ? img.ColorRgb8(195, 195, 195)
              : img.ColorRgb8(25, 25, 25),
        );
      }
    }
    return image;
  }

  Future<String> writeImage(String name, img.Image image) async {
    final file = File('${directory.path}/$name.png');
    await file.writeAsBytes(img.encodePng(image));
    return file.path;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reseebo-image-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => directory.path,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
  });

  test(
    'quality triage distinguishes sharp text from a heavily blurred photo',
    () async {
      final sharpPath = await writeImage('sharp', receipt());
      final blurryPath = await writeImage(
        'blurred',
        img.gaussianBlur(receipt(), radius: 8),
      );
      final sharp = await service.inspectQuality(sharpPath);
      final blurry = await service.inspectQuality(blurryPath);
      expect(sharp.needsRetake, isFalse);
      expect(blurry.needsRetake, isTrue);
      expect(blurry.sharpness, lessThan(sharp.sharpness));
    },
  );

  test(
    'recognition enhancement increases faded ink contrast without modifying original',
    () async {
      final path = await writeImage('faded', receipt(faded: true));
      final original = await File(path).readAsBytes();
      final prepared = await service.prepareRecognition(path);
      final image = img.decodeImage(await File(prepared).readAsBytes())!;
      expect(image.getPixel(48, 53).r, lessThan(100));
      expect(image.getPixel(20, 20).r, greaterThan(230));
      expect(await File(path).readAsBytes(), original);
      expect(prepared, isNot(path));
    },
  );

  test(
    'straightening preserves faded ink enhancement and fills margins with paper white',
    () async {
      final path = await writeImage('faded-tilted', receipt(faded: true));
      final original = await File(path).readAsBytes();
      final corrected = await service.transform(path, angleDegrees: 4);
      final rotated = img.decodeImage(await File(corrected).readAsBytes())!;
      expect(rotated.getPixel(0, 0).r, greaterThan(230));
      final prepared = await service.prepareRecognition(corrected);
      final enhanced = img.decodeImage(await File(prepared).readAsBytes())!;
      expect(
        enhanced.where((pixel) => pixel.r < 100).length,
        greaterThan(1000),
      );
      expect(await File(path).readAsBytes(), original);
    },
  );

  test(
    'crop and rotate keep original bytes and produce the requested geometry',
    () async {
      final path = await writeImage('source', receipt());
      final original = await File(path).readAsBytes();
      final cropped = await service.transform(
        path,
        crop: [0.25, 0.25, 0.75, 0.75],
      );
      final rotated = await service.transform(cropped, rotate: true);
      final result = img.decodeImage(await File(rotated).readAsBytes())!;
      expect(result.width, 400);
      expect(result.height, 300);
      expect(await File(path).readAsBytes(), original);
    },
  );

  test(
    'angle correction rejects invalid angles and accepts a small correction',
    () async {
      final path = await writeImage('angled', receipt());
      await expectLater(
        service.transform(path, angleDegrees: double.nan),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        service.transform(path, angleDegrees: 45),
        throwsA(isA<AppException>()),
      );
      final corrected = await service.transform(path, angleDegrees: -4);
      expect(img.decodeImage(await File(corrected).readAsBytes()), isNotNull);
    },
  );

  test('quality triage rejects a blank frame and unreadable image', () async {
    final blank = img.Image(width: 600, height: 800);
    img.fill(blank, color: img.ColorRgb8(255, 255, 255));
    expect(
      (await service.inspectQuality(
        await writeImage('blank', blank),
      )).needsRetake,
      isTrue,
    );
    final file = File('${directory.path}/invalid.jpg');
    await file.writeAsString('not an image');
    await expectLater(
      service.inspectQuality(file.path),
      throwsA(isA<AppException>()),
    );
  });
}
