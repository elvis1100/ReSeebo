import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../errors/app_exception.dart';
import '../models/models.dart';
import '../models/ocr_engine.dart';
import 'ocr_service.dart';
import 'paddle_ocr_service.dart';

class OcrEngineRegistry {
  OcrEngineRegistry({
    OcrService? mlKitService,
    List<OcrEngineDescriptor>? descriptors,
    Map<OcrEngineId, OcrService Function()>? engineFactories,
  }) : _mlKit = mlKitService ?? MlKitOcrService(),
       descriptors = List.unmodifiable([
         mlKitDescriptor,
         for (final id in OcrEngineId.values.where(
           (id) => id != OcrEngineId.mlKit,
         ))
           (descriptors ?? const <OcrEngineDescriptor>[])
                   .where((d) => d.id == id)
                   .firstOrNull ??
               OcrEngineDescriptor(
                 id: id,
                 label: _labels[id]!,
                 modelVersion: 'unpackaged',
                 runtimeVersion: 'unpackaged',
                 available: false,
                 unavailableReason:
                     'This engine has not been bundled and verified.',
               ),
       ]),
       _factories = Map.of(engineFactories ?? const {}) {
    for (final descriptor in this.descriptors) {
      if (descriptor.id != OcrEngineId.mlKit && descriptor.available) {
        _factories.putIfAbsent(
          descriptor.id,
          () =>
              () => PaddleOcrService(descriptor: descriptor),
        );
      }
    }
  }

  static const mlKitDescriptor = OcrEngineDescriptor(
    id: OcrEngineId.mlKit,
    label: 'ML Kit Latin',
    modelVersion: '16.0.1',
    runtimeVersion: 'google_mlkit_text_recognition-0.16.0',
    available: true,
  );
  static const _labels = {
    OcrEngineId.ppOcrV5Mobile: 'PP-OCRv5 Mobile',
    OcrEngineId.ppOcrV6Medium: 'PP-OCRv6 Medium',
  };
  final List<OcrEngineDescriptor> descriptors;
  final OcrService _mlKit;
  final Map<OcrEngineId, OcrService Function()> _factories;
  OcrEngineId? _loadedId;
  OcrService? _loaded;
  Future<void> _pending = Future.value();
  Future<void>? _closing;
  bool _closed = false;

  OcrEngineDescriptor descriptorFor(OcrEngineId id) =>
      descriptors.firstWhere((descriptor) => descriptor.id == id);

  /// Runtime loads only packaged assets. A missing or invalid manifest leaves
  /// the separately bundled ML Kit path available, with Paddle disabled.
  static Future<OcrEngineRegistry> loadBundled({
    OcrService? mlKitService,
  }) async {
    try {
      final value = jsonDecode(
        await rootBundle.loadString('assets/ocr/model_manifest.json'),
      );
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid OCR manifest.');
      }
      return await fromManifest(value, mlKitService: mlKitService);
    } catch (_) {
      return OcrEngineRegistry(mlKitService: mlKitService);
    }
  }

  /// Paddle availability requires device proof, exact asset hashes and an
  /// installed native capability with matching model/runtime identity.
  static Future<OcrEngineRegistry> fromManifest(
    Map<String, dynamic> manifest, {
    OcrService? mlKitService,
    Future<ByteData> Function(String)? loadAsset,
    Future<List<dynamic>> Function()? nativeEngines,
  }) async {
    if (manifest['schemaVersion'] != 1 || manifest['engines'] is! List) {
      throw const FormatException('Unsupported OCR manifest.');
    }
    final seen = <OcrEngineId>{};
    final descriptors = <OcrEngineDescriptor>[];
    List<dynamic>? capabilities;
    for (final value in manifest['engines'] as List) {
      if (value is! Map) {
        throw const FormatException('Invalid OCR manifest engine.');
      }
      String text(String key) {
        final item = value[key];
        if (item is! String || item.trim().isEmpty) {
          throw FormatException('Invalid OCR engine $key.');
        }
        return item;
      }

      final id = OcrEngineId.fromWireId(text('id'));
      if (!seen.add(id)) throw const FormatException('Duplicate OCR engine.');
      final label = text('label');
      final model = text('modelVersion');
      final runtime = text('runtimeVersion');
      if (value['available'] is! bool ||
          value['verifiedOnDevice'] is! bool ||
          value['artifacts'] is! List) {
        throw const FormatException('Invalid OCR availability proof.');
      }
      if (id == OcrEngineId.mlKit) continue;
      var available = false;
      var reason =
          value['unavailableReason'] as String? ??
          'This engine has not been bundled and verified.';
      final artifacts = value['artifacts'] as List;
      if (value['available'] == true &&
          value['verifiedOnDevice'] == true &&
          artifacts.isNotEmpty) {
        try {
          for (final artifact in artifacts) {
            if (artifact is! Map ||
                artifact['path'] is! String ||
                artifact['sha256'] is! String ||
                !(artifact['path'] as String).startsWith('assets/ocr/') ||
                !RegExp(
                  r'^[a-f0-9]{64}$',
                ).hasMatch(artifact['sha256'] as String)) {
              throw const FormatException('Invalid OCR artifact identity.');
            }
            final data = await (loadAsset ?? rootBundle.load)(
              artifact['path'] as String,
            );
            if (sha256
                    .convert(
                      data.buffer.asUint8List(
                        data.offsetInBytes,
                        data.lengthInBytes,
                      ),
                    )
                    .toString() !=
                artifact['sha256']) {
              throw const FormatException('Bundled OCR asset hash mismatch.');
            }
          }
          capabilities ??=
              await (nativeEngines ??
                  () async =>
                      await const MethodChannel(
                        'reseebo/ocr',
                      ).invokeListMethod<dynamic>('engines') ??
                      const [])();
          available = capabilities.any(
            (item) =>
                item is Map &&
                item['engineId'] == id.wireId &&
                item['modelVersion'] == model &&
                item['runtimeVersion'] == runtime,
          );
          if (!available) {
            reason =
                'The bundled native runtime does not support this exact model.';
          }
        } catch (_) {
          reason = 'The bundled model or native runtime could not be verified.';
        }
      }
      descriptors.add(
        OcrEngineDescriptor(
          id: id,
          label: label,
          modelVersion: model,
          runtimeVersion: runtime,
          available: available,
          unavailableReason: available ? null : reason,
        ),
      );
    }
    return OcrEngineRegistry(
      mlKitService: mlKitService,
      descriptors: descriptors,
    );
  }

  Future<List<OcrTextLine>> recognize(OcrEngineId engineId, String imagePath) {
    if (_closed) return Future.error(StateError('The OCR registry is closed.'));
    final result = _pending.then((_) async {
      final descriptor = descriptorFor(engineId);
      if (!descriptor.available) {
        throw AppException(
          '${descriptor.label}: ${descriptor.unavailableReason ?? 'Unavailable.'}',
        );
      }
      if (_loadedId != engineId) {
        final previous = _loaded;
        _loaded = null;
        _loadedId = null;
        if (previous != null) await previous.close();
      }
      final OcrService service;
      if (engineId == OcrEngineId.mlKit) {
        service = _mlKit;
      } else {
        service = _loaded ??= _factories[engineId]!();
        _loadedId = engineId;
      }
      try {
        return await service.recognize(imagePath);
      } catch (error) {
        throw AppException(
          '${descriptor.label}: ${error is AppException ? error.message : error}',
        );
      }
    });
    _pending = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  /// Drains accepted work and frees the heavy session. Later recognition may
  /// lazily load it again; releasing a capture must not close shared storage.
  Future<void> releaseLoadedEngine() {
    if (_closed) return _closing ?? Future.value();
    final result = _pending.then((_) async {
      final loaded = _loaded;
      _loaded = null;
      _loadedId = null;
      if (loaded != null) await loaded.close();
    });
    _pending = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  /// Reject new work immediately, drain accepted inference, then release once.
  Future<void> close() {
    _closed = true;
    return _closing ??= _pending.then((_) async {
      final loaded = _loaded;
      _loaded = null;
      _loadedId = null;
      try {
        if (loaded != null) await loaded.close();
      } finally {
        await _mlKit.close();
      }
    });
  }
}
