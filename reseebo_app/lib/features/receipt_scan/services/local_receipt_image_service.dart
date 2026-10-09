import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../../core/errors/app_exception.dart';
import '../models/receipt_image_quality.dart';

img.Image _readImage(String path) {
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) {
    throw const AppException(
      'This photo could not be read. Choose another receipt image.',
    );
  }
  return img.bakeOrientation(decoded);
}

Uint8List _transformImage(Map<String, Object> input) {
  var image = _readImage(input['path']! as String);
  if (input['rotate'] != null) {
    // Rotated margins are paper, not dark ink. Black padding would skew the
    // contrast percentiles and weaken enhancement of a faded receipt.
    image.backgroundColor = img.ColorRgb8(255, 255, 255);
    image = img.copyRotate(
      image,
      angle: input['rotate']! as num,
      interpolation: img.Interpolation.linear,
    );
  }
  if (input['crop'] != null) {
    final crop = input['crop']! as List<double>;
    image = img.copyCrop(
      image,
      x: (crop[0] * image.width).floor(),
      y: (crop[1] * image.height).floor(),
      width: ((crop[2] - crop[0]) * image.width).floor().clamp(1, image.width),
      height: ((crop[3] - crop[1]) * image.height).floor().clamp(
        1,
        image.height,
      ),
    );
  }
  if (input['enhance'] == true) {
    image = img.grayscale(image);
    final histogram = List<int>.filled(256, 0);
    for (final pixel in image) {
      histogram[pixel.r.toInt().clamp(0, 255)]++;
    }
    final count = image.width * image.height;
    int percentile(double fraction) {
      var sum = 0;
      for (var value = 0; value < 256; value++) {
        sum += histogram[value];
        if (sum >= count * fraction) return value;
      }
      return 255;
    }

    final low = percentile(.01);
    final high = percentile(.99);
    // Stretch faded ink without hard thresholding away fine strokes. A nearly
    // blank frame has no useful range to stretch and remains unchanged.
    if (high - low > 4) {
      for (final pixel in image) {
        final value = ((pixel.r - low) * 255 / (high - low)).round().clamp(
          0,
          255,
        );
        pixel.setRgb(value, value, value);
      }
    }
  }
  final contrast = input['contrast'] as double? ?? 1;
  if (contrast != 1) {
    for (final pixel in image) {
      pixel.setRgb(
        ((pixel.r - 128) * contrast + 128).round().clamp(0, 255),
        ((pixel.g - 128) * contrast + 128).round().clamp(0, 255),
        ((pixel.b - 128) * contrast + 128).round().clamp(0, 255),
      );
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

ReceiptImageQuality _inspectQuality(String path) {
  final original = _readImage(path);
  final image = original.width > 1000 || original.height > 1000
      ? img.copyResize(
          original,
          width: original.width >= original.height ? 1000 : null,
          height: original.height > original.width ? 1000 : null,
          interpolation: img.Interpolation.average,
        )
      : original;
  final width = image.width;
  final height = image.height;
  final luminance = Float64List(width * height);
  var sum = 0.0;
  var squares = 0.0;
  for (final pixel in image) {
    final value = pixel.r * .299 + pixel.g * .587 + pixel.b * .114;
    luminance[pixel.y * width + pixel.x] = value;
    sum += value;
    squares += value * value;
  }
  final count = width * height;
  final variance = count == 0
      ? 0.0
      : squares / count - (sum / count) * (sum / count);
  var edgeSum = 0.0;
  var edgeSquares = 0.0;
  var edgeCount = 0;
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final index = y * width + x;
      final edge =
          luminance[index - 1] +
          luminance[index + 1] +
          luminance[index - width] +
          luminance[index + width] -
          4 * luminance[index];
      edgeSum += edge;
      edgeSquares += edge * edge;
      edgeCount++;
    }
  }
  final sharpness = edgeCount == 0
      ? 0.0
      : edgeSquares / edgeCount - (edgeSum / edgeCount) * (edgeSum / edgeCount);
  return ReceiptImageQuality(
    width: original.width,
    height: original.height,
    sharpness: sharpness.clamp(0, double.infinity),
    contrast: variance.clamp(0, double.infinity),
  );
}

class LocalReceiptImageService {
  /// Measures the unenhanced, orientation-corrected photo in a worker isolate.
  /// Contrast and sharpness are pixel variances, not probabilities of accuracy.
  Future<ReceiptImageQuality> inspectQuality(String path) =>
      compute(_inspectQuality, path);

  /// Bakes orientation into a cache JPEG and optionally stretches grayscale
  /// contrast. The original is never overwritten; OCR bounds refer to this copy.
  Future<String> prepareRecognition(
    String path, {
    bool enhance = true,
    double contrast = 1,
  }) {
    if (!contrast.isFinite || contrast < .5 || contrast > 2) {
      throw const AppException('Choose contrast between 0.5 and 2.');
    }
    return _writeTransform({
      'path': path,
      'enhance': enhance,
      'contrast': contrast,
    });
  }

  /// Cleanup is limited to cache files created by this service, never originals
  /// or user-selected photos. Failure to clean cache must not discard a draft.
  Future<void> deleteGenerated(
    Iterable<String?> paths, {
    required String originalPath,
  }) async {
    for (final path in paths.whereType<String>().toSet()) {
      if (path == originalPath ||
          !path.split('/').last.startsWith('reseebo_recognition_')) {
        continue;
      }
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // The operating system can remove leftover temporary cache files.
      }
    }
  }

  Future<String> hash(String path) async {
    final file = File(path);
    if (!await file.exists() || await file.length() == 0) {
      throw const AppException(
        'A receipt photo is unavailable. Remove it and add the photo again.',
      );
    }
    return (await sha256.bind(file.openRead()).first).toString();
  }

  /// Creates a cache copy for recognition; never changes the original photo.
  /// Crop edges are normalized left/top/right/bottom coordinates in [0, 1].
  Future<String> transform(
    String path, {
    bool rotate = false,
    List<double>? crop,
    double angleDegrees = 0,
  }) async {
    if (!angleDegrees.isFinite || angleDegrees.abs() > 15) {
      throw const AppException(
        'Choose an angle correction between -15 and 15 degrees.',
      );
    }
    if (crop != null &&
        (crop.length != 4 ||
            crop.any((edge) => !edge.isFinite || edge < 0 || edge > 1) ||
            crop[0] >= crop[2] ||
            crop[1] >= crop[3])) {
      throw const AppException('Choose a valid crop area.');
    }
    final input = <String, Object>{'path': path};
    if (rotate || angleDegrees != 0) {
      input['rotate'] = (rotate ? 90 : 0) + angleDegrees;
    }
    if (crop != null) input['crop'] = crop;
    return _writeTransform(input);
  }

  Future<String> _writeTransform(Map<String, Object> input) async {
    final bytes = await compute(_transformImage, input);
    final directory = await getTemporaryDirectory();
    final destination =
        '${directory.path}/reseebo_recognition_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(destination).writeAsBytes(bytes, flush: true);
    return destination;
  }
}
