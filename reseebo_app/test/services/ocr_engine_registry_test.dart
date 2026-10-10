import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/models/ocr_engine.dart';
import 'package:reseebo_app/core/services/ocr_engine_registry.dart';
import 'package:reseebo_app/core/services/ocr_service.dart';
import 'package:reseebo_app/core/services/paddle_ocr_service.dart';

class RecordingOcr implements OcrService {
  RecordingOcr({this.gate});
  final Completer<void>? gate;
  final calls = <String>[];
  int closes = 0;
  @override
  Future<List<OcrTextLine>> recognize(String imagePath) async {
    calls.add(imagePath);
    await gate?.future;
    return [OcrTextLine(text: imagePath)];
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

const paddle = OcrEngineDescriptor(
  id: OcrEngineId.ppOcrV5Mobile,
  label: 'PP-OCRv5 Mobile',
  modelVersion: 'test-model',
  runtimeVersion: 'test-runtime',
  available: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('registry_serializes_native_work', () async {
    final gate = Completer<void>();
    final service = RecordingOcr(gate: gate);
    final registry = OcrEngineRegistry(mlKitService: service);
    final first = registry.recognize(OcrEngineId.mlKit, 'one');
    final second = registry.recognize(OcrEngineId.mlKit, 'two');
    await Future<void>.delayed(Duration.zero);
    expect(service.calls, ['one']);
    gate.complete();
    expect((await first).single.text, 'one');
    expect((await second).single.text, 'two');
    await registry.close();
  });

  test('close_releases_loaded_engine_once', () async {
    final mlKit = RecordingOcr();
    final heavy = RecordingOcr();
    final registry = OcrEngineRegistry(
      mlKitService: mlKit,
      descriptors: [paddle],
      engineFactories: {OcrEngineId.ppOcrV5Mobile: () => heavy},
    );
    await registry.recognize(OcrEngineId.ppOcrV5Mobile, 'page');
    await Future.wait([registry.close(), registry.close()]);
    expect(heavy.closes, 1);
    expect(mlKit.closes, 1);
    await expectLater(
      registry.recognize(OcrEngineId.mlKit, 'late'),
      throwsA(isA<StateError>()),
    );
  });

  test('release_session_preserves_registry_for_reopening_capture', () async {
    final services = <RecordingOcr>[];
    final registry = OcrEngineRegistry(
      mlKitService: RecordingOcr(),
      descriptors: [paddle],
      engineFactories: {
        OcrEngineId.ppOcrV5Mobile: () {
          final service = RecordingOcr();
          services.add(service);
          return service;
        },
      },
    );
    await registry.recognize(OcrEngineId.ppOcrV5Mobile, 'first');
    await registry.releaseLoadedEngine();
    expect(services.single.closes, 1);
    expect(
      (await registry.recognize(
        OcrEngineId.ppOcrV5Mobile,
        'second',
      )).single.text,
      'second',
    );
    expect(services, hasLength(2));
    await registry.close();
  });

  test('release_session_drains_active_inference_before_disposal', () async {
    final gate = Completer<void>();
    final heavy = RecordingOcr(gate: gate);
    final registry = OcrEngineRegistry(
      mlKitService: RecordingOcr(),
      descriptors: [paddle],
      engineFactories: {OcrEngineId.ppOcrV5Mobile: () => heavy},
    );
    final reading = registry.recognize(OcrEngineId.ppOcrV5Mobile, 'page');
    await Future<void>.delayed(Duration.zero);
    final release = registry.releaseLoadedEngine();
    expect(heavy.closes, 0);
    gate.complete();
    await reading;
    await release;
    expect(heavy.closes, 1);
    await registry.close();
  });

  test('switch_releases_heavy_engine_before_next_inference', () async {
    final events = <String>[];
    final registry = OcrEngineRegistry(
      mlKitService: _EventOcr(events, 'mlkit'),
      descriptors: [paddle],
      engineFactories: {
        OcrEngineId.ppOcrV5Mobile: () => _EventOcr(events, 'paddle'),
      },
    );
    await registry.recognize(OcrEngineId.ppOcrV5Mobile, 'page');
    await registry.recognize(OcrEngineId.mlKit, 'page');
    expect(events, ['paddle:recognize', 'paddle:close', 'mlkit:recognize']);
    await registry.close();
  });

  test('unverified_manifest_never_enables_requested_engines', () async {
    final registry = await OcrEngineRegistry.fromManifest({
      'schemaVersion': 1,
      'engines': [
        {
          'id': 'ppocr_v5_mobile',
          'label': 'PP-OCRv5 Mobile',
          'modelVersion': '5',
          'runtimeVersion': '1',
          'available': true,
          'verifiedOnDevice': false,
          'artifacts': <Object>[],
        },
      ],
    }, mlKitService: RecordingOcr());
    expect(
      registry.descriptors
          .singleWhere((d) => d.id == OcrEngineId.ppOcrV5Mobile)
          .available,
      false,
    );
    await expectLater(
      registry.recognize(OcrEngineId.ppOcrV5Mobile, 'page'),
      throwsA(isA<Exception>()),
    );
    await registry.close();
  });

  for (final fixture in [
    (
      name: 'matching_artifact_and_native_identity_enables_engine',
      bytes: <int>[97, 98, 99],
      nativeModel: 'test-model',
      nativeRuntime: 'test-runtime',
      available: true,
    ),
    (
      name: 'mismatched_artifact_hash_disables_engine',
      bytes: <int>[97, 98, 100],
      nativeModel: 'test-model',
      nativeRuntime: 'test-runtime',
      available: false,
    ),
    (
      name: 'mismatched_native_model_disables_engine',
      bytes: <int>[97, 98, 99],
      nativeModel: 'other-model',
      nativeRuntime: 'test-runtime',
      available: false,
    ),
    (
      name: 'mismatched_native_runtime_disables_engine',
      bytes: <int>[97, 98, 99],
      nativeModel: 'test-model',
      nativeRuntime: 'other-runtime',
      available: false,
    ),
  ]) {
    test(fixture.name, () async {
      final loadedPaths = <String>[];
      final registry = await OcrEngineRegistry.fromManifest(
        {
          'schemaVersion': 1,
          'engines': [
            {
              'id': 'ppocr_v5_mobile',
              'label': 'PP-OCRv5 Mobile',
              'modelVersion': 'test-model',
              'runtimeVersion': 'test-runtime',
              'available': true,
              'verifiedOnDevice': true,
              'artifacts': [
                {
                  'path': 'assets/ocr/test/model.bin',
                  'sha256':
                      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
                },
              ],
            },
          ],
        },
        mlKitService: RecordingOcr(),
        loadAsset: (path) async {
          loadedPaths.add(path);
          return ByteData.sublistView(Uint8List.fromList(fixture.bytes));
        },
        nativeEngines: () async => [
          {
            'engineId': 'ppocr_v5_mobile',
            'modelVersion': fixture.nativeModel,
            'runtimeVersion': fixture.nativeRuntime,
          },
        ],
      );
      expect(loadedPaths, ['assets/ocr/test/model.bin']);
      expect(
        registry.descriptorFor(OcrEngineId.ppOcrV5Mobile).available,
        fixture.available,
      );
      expect(registry.descriptorFor(OcrEngineId.mlKit).available, true);
      if (!fixture.available) {
        await expectLater(
          registry.recognize(OcrEngineId.ppOcrV5Mobile, 'page'),
          throwsA(isA<Exception>()),
        );
      }
      await registry.close();
    });
  }

  test('run_metadata_roundtrips_and_rejects_unknown_engine', () {
    const run = OcrRunMetadata(
      engineId: OcrEngineId.ppOcrV5Mobile,
      modelVersion: '5',
      runtimeVersion: '1',
      parserVersion: '1',
      inputDigest: 'abc',
      preprocessingRevision: 'crop-2',
      elapsedMs: 52,
    );
    final decoded = OcrRunMetadata.fromJson(run.toJson());
    expect(decoded.engineId, OcrEngineId.ppOcrV5Mobile);
    expect(decoded.elapsedMs, 52);
    expect(decoded.preprocessingRevision, 'crop-2');
    expect(decoded.toJson(), run.toJson());
    expect(
      () => OcrRunMetadata.fromJson({...run.toJson(), 'engineId': 'unknown'}),
      throwsFormatException,
    );
    expect(
      () => OcrRunMetadata.fromJson({...run.toJson(), 'elapsedMs': -1}),
      throwsFormatException,
    );
  });

  test('paddle_wire_preserves_line_bounds_without_invented_tokens', () async {
    const channel = MethodChannel('reseebo/ocr');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'release') return null;
          return {
            'engineId': 'ppocr_v5_mobile',
            'modelVersion': 'test-model',
            'runtimeVersion': 'test-runtime',
            'elapsedMs': 12,
            'imageWidth': 100,
            'imageHeight': 200,
            'lines': [
              {
                'text': 'Coffee',
                'left': 10.0,
                'top': 20.0,
                'width': 30.0,
                'height': 8.0,
              },
            ],
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final service = PaddleOcrService(descriptor: paddle);
    final lines = await service.recognize('/page.jpg');
    expect(lines.single.left, 10);
    expect(lines.single.tokens, isEmpty);
    expect(calls.single.arguments, {
      'engineId': 'ppocr_v5_mobile',
      'imagePath': '/page.jpg',
    });
    await service.close();
    await service.close();
    expect(calls.map((c) => c.method), ['recognize', 'release']);
  });

  test('paddle_preserves_blank_detection_alongside_readable_text', () async {
    const channel = MethodChannel('reseebo/ocr');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'release') return null;
          return {
            'engineId': 'ppocr_v5_mobile',
            'modelVersion': 'test-model',
            'runtimeVersion': 'test-runtime',
            'elapsedMs': 1,
            'imageWidth': 100,
            'imageHeight': 200,
            'lines': [
              {'text': '', 'left': 1, 'top': 1, 'width': 20, 'height': 5},
              {
                'text': 'Coffee',
                'left': 1,
                'top': 10,
                'width': 20,
                'height': 5,
              },
            ],
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final service = PaddleOcrService(descriptor: paddle);
    final lines = await service.recognize('/page');
    expect(lines.map((line) => line.text), ['', 'Coffee']);
    expect(lines.first.width, 20);
    await service.close();
  });
}

class _EventOcr implements OcrService {
  _EventOcr(this.events, this.name);
  final List<String> events;
  final String name;
  @override
  Future<List<OcrTextLine>> recognize(String path) async {
    events.add('$name:recognize');
    return const [OcrTextLine(text: 'Store')];
  }

  @override
  Future<void> close() async {
    events.add('$name:close');
  }
}
