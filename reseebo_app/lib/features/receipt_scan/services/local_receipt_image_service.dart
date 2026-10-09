import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../../core/errors/app_exception.dart';

Uint8List _transformImage(Map<String, Object> input) {
  final decoded = img.decodeImage(
    File(input['path']! as String).readAsBytesSync(),
  );
  if (decoded == null) {
    throw const AppException(
      'This photo could not be read. Choose another receipt image.',
    );
  }
  var image = img.bakeOrientation(decoded);
  if (input['rotate'] != null) {
    image = img.copyRotate(image, angle: input['rotate']! as int);
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
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

class LocalReceiptImageService {
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
  }) async {
    if (crop != null &&
        (crop.length != 4 ||
            crop.any((edge) => !edge.isFinite || edge < 0 || edge > 1) ||
            crop[0] >= crop[2] ||
            crop[1] >= crop[3])) {
      throw const AppException('Choose a valid crop area.');
    }
    final input = <String, Object>{'path': path};
    if (rotate) input['rotate'] = 90;
    if (crop != null) input['crop'] = crop;
    final bytes = await compute(_transformImage, input);
    final directory = await getTemporaryDirectory();
    final destination =
        '${directory.path}/reseebo_recognition_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(destination).writeAsBytes(bytes, flush: true);
    return destination;
  }
}
