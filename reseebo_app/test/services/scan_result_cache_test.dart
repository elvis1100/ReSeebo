import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/models/ocr_engine.dart';
import 'package:reseebo_app/features/receipt_scan/models/scan_result.dart';
import 'package:reseebo_app/features/receipt_scan/services/scan_result_cache.dart';

void main() {
  late Directory directory;
  late List<String> originals;
  late List<String> recognition;
  late List<String> comparison;
  const descriptor = OcrEngineDescriptor(
    id: OcrEngineId.mlKit,
    label: 'ML Kit Latin',
    modelVersion: 'model-1',
    runtimeVersion: 'runtime-1',
    available: true,
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reseebo-scan-key-');
    Future<String> file(String name, List<int> bytes) async {
      final result = File('${directory.path}/$name');
      await result.writeAsBytes(bytes);
      return result.path;
    }

    originals = [
      await file('original-a', [1, 2]),
      await file('original-b', [3, 4]),
    ];
    recognition = [
      await file('recognition-a', [5, 6]),
      await file('recognition-b', [7, 8]),
    ];
    comparison = [
      await file('comparison-a', [9, 10]),
      await file('comparison-b', [11, 12]),
    ];
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<String> key({
    List<String>? originalPaths,
    List<String>? recognitionPaths,
    List<String>? comparisonPaths,
    List<String>? edits,
    String preprocessing = 'orientation-enhance-1',
    String parser = 'parser-1',
    OcrEngineDescriptor engine = descriptor,
  }) => ScanResultCache.keyFor(
    originalPaths: originalPaths ?? originals,
    recognitionPaths: recognitionPaths ?? recognition,
    comparisonPaths: comparisonPaths ?? comparison,
    photoEditRevisions: edits ?? ['edit-1', 'edit-1'],
    preprocessingRevision: preprocessing,
    engine: engine,
    parserVersion: parser,
  );

  test('content_order_edit_and_version_invalidate', () async {
    final initial = await key();
    expect(await key(), initial);
    expect(
      await key(originalPaths: originals.reversed.toList()),
      isNot(initial),
    );
    expect(
      await key(recognitionPaths: recognition.reversed.toList()),
      isNot(initial),
    );
    expect(
      await key(comparisonPaths: comparison.reversed.toList()),
      isNot(initial),
    );
    expect(await key(edits: ['edit-2', 'edit-1']), isNot(initial));
    expect(await key(preprocessing: 'orientation-enhance-2'), isNot(initial));
    expect(await key(parser: 'parser-2'), isNot(initial));
    for (final engine in [
      const OcrEngineDescriptor(
        id: OcrEngineId.mlKit,
        label: 'label',
        modelVersion: 'model-2',
        runtimeVersion: 'runtime-1',
        available: true,
      ),
      const OcrEngineDescriptor(
        id: OcrEngineId.mlKit,
        label: 'label',
        modelVersion: 'model-1',
        runtimeVersion: 'runtime-2',
        available: true,
      ),
      const OcrEngineDescriptor(
        id: OcrEngineId.ppOcrV5Mobile,
        label: 'label',
        modelVersion: 'model-1',
        runtimeVersion: 'runtime-1',
        available: true,
      ),
    ]) {
      expect(await key(engine: engine), isNot(initial));
    }
    for (final path in [originals.first, recognition.first, comparison.first]) {
      final file = File(path);
      final priorBytes = await file.readAsBytes();
      final priorTime = await file.lastModified();
      await file.writeAsBytes([31, 32]);
      await file.setLastModified(priorTime);
      expect(await key(), isNot(initial), reason: 'actual bytes at $path');
      await file.writeAsBytes(priorBytes);
    }
  });

  test(
    'same bytes at other paths share identity; boundary ambiguity cannot collide',
    () async {
      final initial = await key();
      final copy = File('${directory.path}/copy');
      await copy.writeAsBytes(await File(originals.first).readAsBytes());
      expect(await key(originalPaths: [copy.path, originals.last]), initial);
      expect(
        await key(edits: ['a|b', 'c']),
        isNot(await key(edits: ['a', 'b|c'])),
      );
    },
  );

  test(
    'cached results own a private snapshot on insertion and lookup',
    () async {
      final cache = ScanResultCache();
      final draft = ReceiptDraft(
        rawText: 'original',
        lines: [ParsedLineItem(description: 'Item')],
      );
      final result = ScanResult(
        key: await key(),
        engineId: OcrEngineId.mlKit,
        draft: draft,
        elapsedMs: 12,
      );
      cache.put(result);
      draft.rawText = 'changed';
      final first = cache.get(result.key)!;
      expect(first.draft!.rawText, 'original');
      first.draft!.lines.single.description = 'changed';
      expect(cache.get(result.key)!.draft!.lines.single.description, 'Item');
      cache.clear();
      expect(cache.get(result.key), isNull);
    },
  );

  test('misaligned or missing inputs are rejected before reuse', () async {
    await expectLater(key(edits: ['one']), throwsArgumentError);
    await File(originals.first).delete();
    await expectLater(key(), throwsA(isA<FileSystemException>()));
  });
}
