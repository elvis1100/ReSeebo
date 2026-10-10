import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/sqlite_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/models/ocr_engine.dart';
import 'package:reseebo_app/core/services/ocr_engine_registry.dart';
import 'package:reseebo_app/core/services/ocr_service.dart';
import 'package:reseebo_app/core/services/receipt_parser.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class PageOcr implements OcrService {
  final calls = <String>[];
  String? failingPage;
  @override
  Future<List<OcrTextLine>> recognize(String path) async {
    calls.add(path);
    if (path == failingPage) throw StateError('page failed');
    return [
      const OcrTextLine(
        text: 'STORE',
        left: 10,
        top: 5,
        width: 100,
        height: 10,
      ),
      OcrTextLine(
        text: '2 pcs ${path.contains('one') ? 'Coffee 26g' : 'Soap 50g'} 44.00',
        left: 10,
        top: 30,
        width: 180,
        height: 10,
        tokens: const [
          OcrTextToken(text: '2', left: 10, top: 30, width: 8, height: 10),
        ],
      ),
    ];
  }

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root;
  late List<String> pages;
  late PageOcr mlKit;
  late PageOcr paddle;
  late SqliteReseeboDataAdapter adapter;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('reseebo_engine_');
    pages = [
      for (final name in ['one', 'two'])
        (File('${root.path}/$name.jpg')..writeAsStringSync(name)).absolute.path,
    ];
    mlKit = PageOcr();
    paddle = PageOcr();
    final registry = OcrEngineRegistry(
      mlKitService: mlKit,
      descriptors: const [
        OcrEngineDescriptor(
          id: OcrEngineId.ppOcrV5Mobile,
          label: 'PP-OCRv5 Mobile',
          modelVersion: '5',
          runtimeVersion: '1',
          available: true,
        ),
      ],
      engineFactories: {OcrEngineId.ppOcrV5Mobile: () => paddle},
    );
    adapter = await SqliteReseeboDataAdapter.open(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${root.path}/db.sqlite',
      mediaDirectory: Directory('${root.path}/media'),
      ocrRegistry: registry,
      starterProducts: const [],
    );
  });
  tearDown(() async {
    await adapter.close();
    await root.delete(recursive: true);
  });
  test('selected_engine_reads_every_page', () async {
    final draft = await adapter.processReceiptImages(
      pages,
      engineId: OcrEngineId.ppOcrV5Mobile,
      preprocessingRevision: 'crop-2',
    );
    expect(paddle.calls, pages);
    expect(mlKit.calls, isEmpty);
    expect(draft.imagePaths, pages);
    expect(draft.ocrRun!.engineId, OcrEngineId.ppOcrV5Mobile);
    expect(draft.ocrRun!.parserVersion, ReceiptParser.version);
    expect(draft.ocrRun!.preprocessingRevision, 'crop-2');
    expect(draft.ocrRun!.inputDigest, matches(RegExp('^[a-f0-9]{64}\$')));
  });
  test('engine_failure_never_calls_fallback', () async {
    paddle.failingPage = pages[1];
    await expectLater(
      adapter.processReceiptImages(pages, engineId: OcrEngineId.ppOcrV5Mobile),
      throwsA(isA<Exception>()),
    );
    expect(paddle.calls, pages);
    expect(mlKit.calls, isEmpty);
  });
  test('shared_parser_keeps_page_provenance', () async {
    final draft = await adapter.processReceiptImages(
      pages,
      engineId: OcrEngineId.ppOcrV5Mobile,
    );
    expect(draft.lines.map((line) => line.sourcePage), [0, 1]);
    expect(draft.ocrPages[1].imagePath, pages[1]);
    expect(draft.ocrPages[1].textLines[1].left, 10);
    expect(draft.ocrPages[1].textLines[1].tokens.single.width, 8);
  });
  test('omitted_engine_keeps_legacy_mlkit_default', () async {
    final draft = await adapter.processReceiptImage(pages.first);
    expect(mlKit.calls, [pages.first]);
    expect(paddle.calls, isEmpty);
    expect(draft.ocrRun!.engineId, OcrEngineId.mlKit);
  });
  test('run_digest_changes_when_page_order_changes', () async {
    final first = await adapter.processReceiptImages(pages);
    final second = await adapter.processReceiptImages(pages.reversed.toList());
    expect(second.ocrRun!.inputDigest, isNot(first.ocrRun!.inputDigest));
  });
}
