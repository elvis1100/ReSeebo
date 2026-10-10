import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/models/ocr_engine.dart';
import 'package:reseebo_app/features/receipt_scan/models/scan_result.dart';
import 'package:reseebo_app/features/receipt_scan/screens/capture_screen.dart';
import 'package:reseebo_app/features/receipt_scan/state/capture_state.dart';

import 'fixtures/receipt_scan_widget_fixture.dart';

class _ProfileImages extends FixtureScanImages {
  _ProfileImages(this.directory);
  final Directory directory;
  int hashCalls = 0;
  @override
  Future<String> hash(String path) {
    hashCalls++;
    return super.hash(path);
  }

  @override
  Future<String> prepareRecognition(
    String path, {
    bool enhance = true,
    double contrast = 1,
  }) async {
    final name = File(path).uri.pathSegments.last.replaceAll('.geometry', '');
    return (await File(
      path,
    ).copy('${directory.path}/$name.recognition.jpg')).path;
  }

  @override
  Future<String> transform(
    String path, {
    bool rotate = false,
    List<double>? crop,
    double angleDegrees = 0,
  }) async {
    return (await File(path).copy(
      '${directory.path}/${File(path).uri.pathSegments.last}.geometry.jpg',
    )).path;
  }
}

class _ProfileCapture extends CaptureState {
  _ProfileCapture({required super.adapter, required super.imageService});
  int synchronousAuthorityReads = 0;
  @override
  ScanResult? resultForEngine(OcrEngineId id) {
    synchronousAuthorityReads++;
    return super.resultForEngine(id);
  }
}

void main() {
  const enabled = bool.fromEnvironment('OCR_PRESENTATION_PROFILE');
  final manifest = File(
    '../.superpowers/sdd/2026-10-10-ocr-selector-and-review-ledger/task-7-profile-inputs/manifest.json',
  );
  testWidgets(
    'host profile keeps twenty large-photo presentation builds free of authority hashing',
    (tester) async {
      final input =
          jsonDecode(await tester.runAsync(manifest.readAsString) ?? '')
              as Map<String, dynamic>;
      final rows = input['pages'] as List<dynamic>;
      final paths = rows
          .map((row) => (row as Map<String, dynamic>)['path'] as String)
          .toList();
      late Directory derived;
      late _ProfileImages images;
      late _ProfileCapture state;
      final adapter = ScanWidgetAdapter();
      final setupWatch = Stopwatch()..start();
      await tester.runAsync(() async {
        derived = await Directory.systemTemp.createTemp(
          'reseebo-host-profile-',
        );
        images = _ProfileImages(derived);
        state = _ProfileCapture(adapter: adapter, imageService: images);
        await state.addImages(paths);
        for (var index = 0; index < paths.length; index++) {
          state.selectPage(index);
          await state.transform(rotate: true);
        }
        await state.recognizeSelected();
      });
      setupWatch.stop();
      addTearDown(() async {
        state.dispose();
        await tester.runAsync(() => derived.delete(recursive: true));
      });
      expect(state.pages, hasLength(20));
      expect(state.selectedPresentationResult, isNotNull);
      final handoffWatch = Stopwatch()..start();
      state.selectedDraftSnapshot();
      handoffWatch.stop();
      state.synchronousAuthorityReads = 0;
      final asyncWatch = Stopwatch()..start();
      var maxTimerGapMs = 0;
      await tester.runAsync(() async {
        final clock = Stopwatch()..start();
        var previous = 0;
        final timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
          final now = clock.elapsedMilliseconds;
          if (now - previous > maxTimerGapMs) maxTimerGapMs = now - previous;
          previous = now;
        });
        try {
          await state.selectedDraftSnapshotAsync();
        } finally {
          timer.cancel();
        }
      });
      asyncWatch.stop();
      expect(state.synchronousAuthorityReads, 0);
      final hashCalls = images.hashCalls;
      final accessorWatch = Stopwatch()..start();
      for (var i = 0; i < 10000; i++) {
        expect(state.selectedPresentationResult, isNotNull);
        expect(state.presentationResults, isNotEmpty);
      }
      accessorWatch.stop();
      expect(state.synchronousAuthorityReads, 0);
      expect(images.hashCalls, hashCalls);
      await tester.pumpWidget(
        scanApp(CaptureScreen(dataAdapter: adapter, captureState: state)),
      );
      await tester.pumpAndSettle();
      state.synchronousAuthorityReads = 0;
      final buildWatch = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        state.selectPage(i % 20);
        await tester.pump();
      }
      buildWatch.stop();
      expect(state.synchronousAuthorityReads, 0);
      expect(images.hashCalls, hashCalls);
      expect(tester.takeException(), isNull);
      final measurements = {
        'environment':
            'Windows Flutter widget-test host; warm filesystem cache, synthetic JPEG receipt photos',
        'pages': 20,
        'pixelsPerOriginal': '3024x4032',
        'originalBytes': input['totalBytes'],
        'activeRoleFiles': 60,
        'activeRoleBytes': (input['totalBytes'] as int) * 3,
        'setupAndFakeRecognitionMs': setupWatch.elapsedMilliseconds,
        'freshSynchronousHandoffMs': handoffWatch.elapsedMilliseconds,
        'freshAsyncHandoffMs': asyncWatch.elapsedMilliseconds,
        'maxObservedAsyncHostTimerGapMs': maxTimerGapMs,
        '10000PresentationAccessPairsMs': accessorWatch.elapsedMilliseconds,
        '100WidgetBuildsMs': buildWatch.elapsedMilliseconds,
        'authorityReadsDuringPresentation': state.synchronousAuthorityReads,
        'limits':
            'No native inference, image processing, device memory or frame-time claim. Derived roles are encoded-file copies. Accessor timing includes assertions; widget time includes test pumping and image presentation.',
      };
      await tester.runAsync(() async {
        final output = File('build/ocr-profile/results.json');
        await output.parent.create(recursive: true);
        await output.writeAsString(jsonEncode(measurements));
      });
    },
    // Opt in with --dart-define=OCR_PRESENTATION_PROFILE=true after generating
    // the declared workload. Ordinary suite runs always skip this host profile.
    skip: !enabled || !manifest.existsSync(),
  );
}
