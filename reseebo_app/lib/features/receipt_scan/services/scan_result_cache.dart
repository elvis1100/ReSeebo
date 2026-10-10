import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../../core/models/ocr_engine.dart';
import '../models/scan_result.dart';

/// Session-local outputs, independent of loaded native model sessions.
class ScanResultCache {
  final Map<String, ScanResult> _results = {};

  ScanResult? get(String key) => _results[key];
  void put(ScanResult result) => _results[result.key] = result;
  void clear() => _results.clear();

  /// Paths are locators only: ordered actual bytes identify all three roles.
  /// Callers must keep the inputs stable through inference and check the key
  /// again before publishing. Missing files fail rather than reuse old output.
  static Future<String> keyFor({
    required List<String> originalPaths,
    required List<String> recognitionPaths,
    required List<String> comparisonPaths,
    required List<String> photoEditRevisions,
    required String preprocessingRevision,
    required OcrEngineDescriptor engine,
    required String parserVersion,
  }) async {
    _validate(
      originalPaths,
      recognitionPaths,
      comparisonPaths,
      photoEditRevisions,
    );
    final byPath = <String, Future<String>>{};
    Future<List<String>> hashes(List<String> paths) async => [
      for (final path in paths)
        await byPath.putIfAbsent(
          path,
          () async =>
              (await sha256.bind(File(path).openRead()).first).toString(),
        ),
    ];
    return _digest(
      await hashes(originalPaths),
      await hashes(recognitionPaths),
      await hashes(comparisonPaths),
      photoEditRevisions,
      preprocessingRevision,
      engine,
      parserVersion,
    );
  }

  /// Synchronous handoff validation closes the gap between an earlier async
  /// read and opening Review/Save. It performs no OCR or image transformation.
  static String keyForSync({
    required List<String> originalPaths,
    required List<String> recognitionPaths,
    required List<String> comparisonPaths,
    required List<String> photoEditRevisions,
    required String preprocessingRevision,
    required OcrEngineDescriptor engine,
    required String parserVersion,
  }) {
    _validate(
      originalPaths,
      recognitionPaths,
      comparisonPaths,
      photoEditRevisions,
    );
    final byPath = <String, String>{};
    List<String> hashes(List<String> paths) => [
      for (final path in paths)
        byPath.putIfAbsent(
          path,
          () => sha256.convert(File(path).readAsBytesSync()).toString(),
        ),
    ];
    return _digest(
      hashes(originalPaths),
      hashes(recognitionPaths),
      hashes(comparisonPaths),
      photoEditRevisions,
      preprocessingRevision,
      engine,
      parserVersion,
    );
  }

  static void _validate(
    List<String> originals,
    List<String> recognition,
    List<String> comparison,
    List<String> edits,
  ) {
    if (originals.isEmpty ||
        recognition.length != originals.length ||
        comparison.length != originals.length ||
        edits.length != originals.length) {
      throw ArgumentError(
        'Scan input roles and edit revisions must align with every original.',
      );
    }
  }

  static String _digest(
    List<String> originals,
    List<String> recognition,
    List<String> comparison,
    List<String> edits,
    String preprocessing,
    OcrEngineDescriptor engine,
    String parser,
  ) => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'original': originals,
            'recognition': recognition,
            'comparison': comparison,
            'edits': edits,
            'preprocessing': preprocessing,
            'engine': engine.id.wireId,
            'model': engine.modelVersion,
            'runtime': engine.runtimeVersion,
            'parser': parser,
          }),
        ),
      )
      .toString();
}
