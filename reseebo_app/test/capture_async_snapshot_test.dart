import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:reseebo_app/core/models/ocr_engine.dart';
import 'package:reseebo_app/features/receipt_scan/models/scan_result.dart';
import 'package:reseebo_app/features/receipt_scan/state/capture_state.dart';

import 'fixtures/receipt_scan_widget_fixture.dart';

class _BlockingHashImages extends FixtureScanImages {
  bool blockNext = false;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<String> hash(String path) async {
    if (blockNext) {
      blockNext = false;
      entered.complete();
      await release.future;
    }
    return super.hash(path);
  }
}

class _AsyncOnlyCapture extends CaptureState {
  _AsyncOnlyCapture({
    required super.adapter,
    required super.imageService,
    required super.initialImagePath,
  });
  @override
  ScanResult? resultForEngine(OcrEngineId id) =>
      throw StateError('Synchronous authority must not run.');
}

void main() {
  late Directory directory;
  late File original;
  late _BlockingHashImages images;
  late ScanWidgetAdapter adapter;
  late _AsyncOnlyCapture state;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'reseebo-async-snapshot-',
    );
    original = File('${directory.path}/receipt.png');
    await original.writeAsBytes(
      image.encodePng(image.Image(width: 600, height: 800)),
    );
    images = _BlockingHashImages();
    adapter = ScanWidgetAdapter();
    state = _AsyncOnlyCapture(
      adapter: adapter,
      imageService: images,
      initialImagePath: original.path,
    );
    await state.recognizeSelected();
    expect(adapter.reads, [OcrEngineId.mlKit]);
  });
  tearDown(() async {
    state.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'async authority yields during hashing and returns a private stable snapshot without OCR',
    () async {
      images.blockNext = true;
      var completed = false;
      final pending = state.selectedDraftSnapshotAsync().then((draft) {
        completed = true;
        return draft;
      });
      await images.entered.future;
      expect(completed, isFalse);
      expect(state.selectedPresentationResult, isNotNull);
      images.release.complete();
      final draft = await pending;
      expect(draft.imagePaths, [original.path]);
      draft.lines.single.description = 'Owner edit';
      final another = await state.selectedDraftSnapshotAsync();
      expect(another.lines.single.description, 'mlKit Coffee');
      expect(adapter.reads, [OcrEngineId.mlKit]);
    },
  );

  for (final mutation in [
    'input revision',
    'engine selection',
    'dispose',
    'external bytes',
  ]) {
    test(
      'async authority refuses $mutation changing during delayed actual-byte validation',
      () async {
        images.blockNext = true;
        final pending = state.selectedDraftSnapshotAsync();
        final refused = expectLater(pending, throwsStateError);
        await images.entered.future;
        switch (mutation) {
          case 'input revision':
            state.setEnhanceForOcr(false);
          case 'engine selection':
            await state.selectEngine(OcrEngineId.ppOcrV5Mobile);
          case 'dispose':
            state.dispose();
          case 'external bytes':
            final bytes = await original.readAsBytes();
            await original.writeAsBytes([...bytes, 0]);
        }
        images.release.complete();
        await refused;
        expect(adapter.reads, [OcrEngineId.mlKit]);
      },
    );
  }
}
