import 'package:flutter/services.dart';

import '../errors/app_exception.dart';
import '../models/models.dart';
import '../models/ocr_engine.dart';
import 'ocr_service.dart';

/// Native inference returns bounds in recognition-input pixels. Missing word
/// bounds stay missing; line rectangles must never be divided into fake words.
class PaddleOcrService implements OcrService {
  PaddleOcrService({required this.descriptor, MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('reseebo/ocr') {
    if (descriptor.id == OcrEngineId.mlKit) {
      throw ArgumentError('Paddle service requires a Paddle engine.');
    }
  }
  final OcrEngineDescriptor descriptor;
  final MethodChannel _channel;
  bool _closed = false;
  Future<void>? _release;

  @override
  Future<List<OcrTextLine>> recognize(String imagePath) async {
    if (_closed) throw StateError('The OCR engine is closed.');
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'recognize',
        {'engineId': descriptor.id.wireId, 'imagePath': imagePath},
      );
      if (result == null ||
          result['engineId'] != descriptor.id.wireId ||
          result['modelVersion'] != descriptor.modelVersion ||
          result['runtimeVersion'] != descriptor.runtimeVersion) {
        throw const FormatException(
          'OCR engine identity does not match the requested engine.',
        );
      }
      final width = _positive(result['imageWidth'], 'imageWidth');
      final height = _positive(result['imageHeight'], 'imageHeight');
      final elapsed = result['elapsedMs'];
      if (elapsed is! int || elapsed < 0 || result['lines'] is! List) {
        throw const FormatException('Invalid OCR result.');
      }
      final lines = <OcrTextLine>[];
      for (final value in result['lines'] as List) {
        final row = _row(value);
        final bounds = _bounds(row, width, height);
        final tokens = <OcrTextToken>[];
        final words = row['tokens'];
        if (words != null && words is! List) {
          throw const FormatException('Invalid OCR tokens.');
        }
        for (final value in (words as List? ?? const [])) {
          final token = _row(value);
          final box = _bounds(token, width, height);
          tokens.add(
            OcrTextToken(
              text: _text(token),
              left: box.$1,
              top: box.$2,
              width: box.$3,
              height: box.$4,
            ),
          );
        }
        lines.add(
          OcrTextLine(
            text: _text(row),
            left: bounds.$1,
            top: bounds.$2,
            width: bounds.$3,
            height: bounds.$4,
            tokens: List.unmodifiable(tokens),
          ),
        );
      }
      if (!lines.any((line) => line.text.trim().isNotEmpty)) {
        throw const ValidationException(
          'No readable receipt text was found. Try a clearer photo or enter the purchase manually.',
        );
      }
      return List.unmodifiable(lines);
    } on PlatformException catch (error) {
      throw AppException('${descriptor.label}: ${error.message ?? error.code}');
    } on MissingPluginException {
      throw AppException(
        '${descriptor.label} is not bundled in this installation.',
      );
    } on FormatException catch (error) {
      throw AppException('${descriptor.label}: ${error.message}');
    }
  }

  static Map<Object?, Object?> _row(Object? value) {
    if (value is! Map) throw const FormatException('Invalid OCR line.');
    return value;
  }

  static String _text(Map<Object?, Object?> value) {
    final text = value['text'];
    if (text is! String) {
      throw const FormatException('Invalid OCR text.');
    }
    return text;
  }

  static double _positive(Object? value, String name) {
    if (value is! num || !value.isFinite || value <= 0) {
      throw FormatException('Invalid OCR $name.');
    }
    return value.toDouble();
  }

  static (double, double, double, double) _bounds(
    Map<Object?, Object?> row,
    double imageWidth,
    double imageHeight,
  ) {
    double number(String key) {
      final value = row[key];
      if (value is! num || !value.isFinite || value < 0) {
        throw FormatException('Invalid OCR $key.');
      }
      return value.toDouble();
    }

    final left = number('left');
    final top = number('top');
    final width = _positive(row['width'], 'width');
    final height = _positive(row['height'], 'height');
    if (left + width > imageWidth + 0.01 || top + height > imageHeight + 0.01) {
      throw const FormatException('OCR bounds exceed the recognition image.');
    }
    return (left, top, width, height);
  }

  /// Release is awaited and idempotent, including concurrent close requests.
  @override
  Future<void> close() {
    _closed = true;
    return _release ??= _channel.invokeMethod<void>('release', {
      'engineId': descriptor.id.wireId,
    });
  }
}
