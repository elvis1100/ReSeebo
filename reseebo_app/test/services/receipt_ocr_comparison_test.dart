import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/sqlite_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/models/ocr_engine.dart';
import 'package:reseebo_app/core/services/ocr_engine_registry.dart';
import 'package:reseebo_app/core/services/ocr_service.dart';
import 'package:reseebo_app/core/services/receipt_ocr_comparison.dart';
import 'package:reseebo_app/core/services/receipt_parser.dart';
import 'package:reseebo_app/core/services/receipt_suggestion_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ReceiptDraft compare(List<String> primary, List<String> original) {
  final page = ReceiptOcrPage(
    imagePath: '/original.jpg',
    recognitionImagePath: '/enhanced.jpg',
    textLines: primary.map((text) => OcrTextLine(text: text)).toList(),
    originalTextLines: original.map((text) => OcrTextLine(text: text)).toList(),
  );
  final draft = ReceiptParser().parsePages(pages: [page]);
  const ReceiptOcrComparison().supplement(draft, [page]);
  return draft;
}

List<OcrTextLine> fixture(String name) {
  final json =
      jsonDecode(
            File('test/fixtures/public_receipts/$name.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  return (json['lines'] as List).map((entry) {
    final row = entry as Map<String, dynamic>;
    return OcrTextLine(
      text: row['text'] as String,
      left: (row['left'] as num).toDouble(),
      top: (row['top'] as num).toDouble(),
      width: (row['width'] as num).toDouble(),
      height: (row['height'] as num).toDouble(),
      tokens: [
        for (final token in (row['tokens'] as List? ?? []))
          OcrTextToken(
            text: token['text'] as String,
            left: (token['left'] as num).toDouble(),
            top: (token['top'] as num).toDouble(),
            width: (token['width'] as num).toDouble(),
            height: (token['height'] as num).toDouble(),
          ),
      ],
    );
  }).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'differing explicit unit prices remain unresolved across original and selected readings',
    () {
      final page = ReceiptOcrPage(
        imagePath: 'original',
        textLines: const [
          OcrTextLine(text: 'STORE'),
          OcrTextLine(text: '2 pcs Coffee 26G @21', left: 10, top: 30),
        ],
        originalTextLines: const [
          OcrTextLine(text: 'STORE'),
          OcrTextLine(text: '2 pcs Coffee 26G @22', left: 100, top: 300),
        ],
      );
      final draft = ReceiptParser().parsePages(pages: [page]);
      const ReceiptOcrComparison().supplement(draft, [page]);
      final line = draft.lines.single;
      expect(line.grossAmountCents, isNull);
      expect(line.extractedUnitPriceCents, 2100);
      expect(
        line.warnings.any((warning) => warning.contains('disagree')),
        isTrue,
      );
      final result = ReceiptSuggestionService().suggest(
        draft,
        products: const [],
        confirmedHistory: const [],
        importedAt: DateTime(2026, 10, 10),
      );
      expect(result.lines.single.grossAmountCents, isNull);
      expect(draft.textLines.last.text, '2 pcs Coffee 26G @21');
      expect(page.originalTextLines.last.text, '2 pcs Coffee 26G @22');
      expect(page.textLines.last.left, 10);
      expect(page.textLines.last.top, 30);
      expect(page.originalTextLines.last.left, 100);
      expect(page.originalTextLines.last.top, 300);
    },
  );
  test(
    'matching original-only explicit unit price supplements evidence without inventing a raw total',
    () {
      final draft = compare(
        ['STORE', '2 pcs Coffee 26G'],
        ['STORE', '2 pcs Coffee 26G @21'],
      );
      expect(draft.lines, hasLength(1));
      expect(draft.lines.single.extractedUnitPriceCents, 2100);
      expect(draft.lines.single.grossAmountCents, isNull);
      expect(draft.lines.single.extractedAmountCents, isNull);
      final result = ReceiptSuggestionService().suggest(
        draft,
        products: const [],
        confirmedHistory: const [],
        importedAt: DateTime(2026, 10, 10),
      );
      expect(result.lines.single.grossAmountCents, 4200);
      expect(
        result.lines.single.provenance[ReceiptSuggestionField.amount]!.origin,
        ReceiptFieldOrigin.calculated,
      );
    },
  );
  test(
    'identical explicit prices remain usable while unsafe supplements stay missing',
    () {
      final same = compare(
        ['STORE', '2 pcs Coffee 26G @21'],
        ['STORE', '2 pcs Coffee 26G @21'],
      );
      expect(
        same.lines.single.warnings.any(
          (warning) => warning.contains('disagree'),
        ),
        isFalse,
      );
      expect(
        ReceiptSuggestionService()
            .suggest(
              same,
              products: const [],
              confirmedHistory: const [],
              importedAt: DateTime(2026, 10, 10),
            )
            .lines
            .single
            .grossAmountCents,
        4200,
      );
      for (final primary in [
        ['STORE', '3 pcs Coffee 26G'],
        ['STORE', '2 packs Coffee 26G'],
        ['STORE', '2 pcs Coffee 26G', '2 pcs Coffee 26G'],
        ['STORE', '2 pcs Coffee 26G @21 @22'],
      ]) {
        final draft = compare(primary, ['STORE', '2 pcs Coffee 26G @21']);
        expect(
          draft.lines.every((line) => line.extractedUnitPriceCents == null),
          isTrue,
          reason: primary.join('|'),
        );
        expect(draft.lines.length, primary.length - 1);
      }
    },
  );
  test('owner-cleared amounts prevent explicit unit-price supplementation', () {
    final page = ReceiptOcrPage(
      imagePath: 'original',
      textLines: const [
        OcrTextLine(text: 'STORE'),
        OcrTextLine(text: '2 pcs Coffee 26G'),
      ],
      originalTextLines: const [
        OcrTextLine(text: 'STORE'),
        OcrTextLine(text: '2 pcs Coffee 26G @21'),
      ],
    );
    final draft = ReceiptParser().parsePages(pages: [page]);
    draft.lines.single.amountEdited = true;
    const ReceiptOcrComparison().supplement(draft, [page]);
    expect(draft.lines.single.extractedUnitPriceCents, isNull);
    expect(draft.lines.single.grossAmountCents, isNull);
  });

  group('selected engine comparison routing', () {
    late Directory root;
    late List<String> originals;
    late List<String> recognition;
    late List<String> comparison;
    late _ComparisonOcr selected;
    late _ComparisonOcr mlKit;
    late SqliteReseeboDataAdapter adapter;

    setUp(() async {
      root = await Directory.systemTemp.createTemp(
        'reseebo_comparison_engine_',
      );
      List<String> files(String prefix) => [
        for (var index = 0; index < 2; index++)
          (File(
            '${root.path}/$prefix-$index.jpg',
          )..writeAsStringSync('$prefix page $index')).path,
      ];
      originals = files('original');
      recognition = files('recognition');
      comparison = files('comparison');
      selected = _ComparisonOcr({
        for (var index = 0; index < 2; index++) ...{
          recognition[index]: [
            const OcrTextLine(text: 'STORE'),
            OcrTextLine(
              text: index == 0 ? 'Coffee 26g' : 'Soap 50g',
              left: 10,
              top: 30,
              width: 80,
              height: 12,
              tokens: [
                OcrTextToken(
                  text: index == 0 ? 'Coffee' : 'Soap',
                  left: 10,
                  top: 30,
                  width: 40,
                  height: 12,
                ),
              ],
            ),
          ],
          comparison[index]: [
            const OcrTextLine(text: 'STORE'),
            OcrTextLine(
              text: index == 0
                  ? '2 pcs Coffee 26g 44.00'
                  : '3 pcs Soap 50g 90.00',
              left: 200,
              top: 300,
              width: 250,
              height: 24,
              tokens: const [
                OcrTextToken(
                  text: 'pcs',
                  left: 220,
                  top: 300,
                  width: 30,
                  height: 24,
                ),
              ],
            ),
          ],
        },
      });
      mlKit = _ComparisonOcr({});
      final registry = OcrEngineRegistry(
        mlKitService: mlKit,
        descriptors: const [
          OcrEngineDescriptor(
            id: OcrEngineId.ppOcrV5Mobile,
            label: 'PP-OCRv5 Mobile',
            modelVersion: 'test-model',
            runtimeVersion: 'test-runtime',
            available: true,
          ),
        ],
        engineFactories: {OcrEngineId.ppOcrV5Mobile: () => selected},
      );
      adapter = await SqliteReseeboDataAdapter.open(
        databaseFactory: databaseFactoryFfi,
        databasePath: '${root.path}/comparison.sqlite',
        mediaDirectory: Directory('${root.path}/media'),
        ocrRegistry: registry,
        starterProducts: const [],
      );
    });
    tearDown(() async {
      await adapter.close();
      await root.delete(recursive: true);
    });

    test(
      'selected_engine_comparison_keeps_distinct_page_coordinate_evidence',
      () async {
        final draft = await adapter.processReceiptImages(
          originals,
          recognitionImagePaths: recognition,
          comparisonImagePaths: comparison,
          engineId: OcrEngineId.ppOcrV5Mobile,
          preprocessingRevision: 'crop-2',
        );
        expect(selected.calls, [
          recognition[0],
          comparison[0],
          recognition[1],
          comparison[1],
        ]);
        expect(mlKit.calls, isEmpty);
        expect(draft.imagePaths, originals);
        expect(draft.ocrRun!.engineId, OcrEngineId.ppOcrV5Mobile);
        expect(draft.ocrRun!.modelVersion, 'test-model');
        expect(draft.ocrRun!.runtimeVersion, 'test-runtime');
        expect(draft.ocrRun!.preprocessingRevision, 'crop-2');
        expect(draft.lines.map((line) => line.sourcePage), [0, 1]);
        expect(draft.lines.map((line) => line.quantity), [2, 3]);
        expect(draft.lines.map((line) => line.grossAmountCents), [4400, 9000]);
        for (var index = 0; index < 2; index++) {
          final page = draft.ocrPages[index];
          expect(page.imagePath, originals[index]);
          expect(page.recognitionImagePath, recognition[index]);
          expect(page.comparisonImagePath, comparison[index]);
          expect(page.textLines[1].left, 10);
          expect(page.textLines[1].top, 30);
          expect(page.textLines[1].tokens.single.left, 10);
          expect(page.originalTextLines[1].left, 200);
          expect(page.originalTextLines[1].top, 300);
          expect(page.originalTextLines[1].tokens.single.left, 220);
          expect(page.originalTextLines[1].tokens.single.height, 24);
        }
        expect(draft.rawText, contains('--- Original photo 2 comparison ---'));
        expect(draft.rawText, contains('3 pcs Soap 50g 90.00'));
        expect(draft.lines.every((line) => !line.confirmed), isTrue);
      },
    );

    test(
      'selected_engine_comparison_failure_warns_without_mlkit_fallback',
      () async {
        selected.failingPath = comparison[1];
        final draft = await adapter.processReceiptImages(
          originals,
          recognitionImagePaths: recognition,
          comparisonImagePaths: comparison,
          engineId: OcrEngineId.ppOcrV5Mobile,
        );
        expect(selected.calls, [
          recognition[0],
          comparison[0],
          recognition[1],
          comparison[1],
        ]);
        expect(mlKit.calls, isEmpty);
        expect(draft.ocrRun!.engineId, OcrEngineId.ppOcrV5Mobile);
        expect(draft.ocrPages[0].originalTextLines, isNotEmpty);
        expect(draft.ocrPages[1].originalTextLines, isEmpty);
        expect(draft.ocrPages[1].recognitionImagePath, recognition[1]);
        expect(draft.ocrPages[1].comparisonImagePath, comparison[1]);
        expect(draft.ocrPages[1].textLines[1].left, 10);
        expect(draft.lines[1].quantity, isNull);
        expect(draft.lines[1].grossAmountCents, isNull);
        expect(
          draft.warnings,
          contains(
            'Photo 2: the original photo could not be compared. Review the enhanced reading.',
          ),
        );
      },
    );
  });

  test(
    'fills missing fields on a unique identical product without adding rows',
    () {
      final draft = compare(
        ['STORE', 'Coffee 26g', 'TOTAL 44.00'],
        [
          'STORE',
          '2 pcs Coffee 26g 44.00',
          '1 pcs Other 1L 50.00',
          'TOTAL 94.00',
        ],
      );
      expect(draft.lines, hasLength(1));
      expect(draft.lines.single.quantity, 2);
      expect(draft.lines.single.grossAmountCents, 4400);
      expect(draft.lines.single.unit, isNull);
      expect(draft.detectedTotalCents, 4400);
      expect(draft.lines.single.confirmed, isFalse);
    },
  );

  test('disagreeing count prevents borrowing missing amount', () {
    final draft = compare(
      ['STORE', '2 pcs Coffee 26g'],
      ['STORE', '3 pcs Coffee 26g 66.00'],
    );
    expect(draft.lines.single.quantity, 2);
    expect(draft.lines.single.grossAmountCents, isNull);
    expect(draft.lines.single.warnings.join(' '), contains('disagree'));
  });

  test('conflicting printed arithmetic cannot be rescued by another pass', () {
    final draft = compare(
      ['STORE', '2 pcs Coffee 26g 22.00 45.00'],
      ['STORE', '2 pcs Coffee 26g 22.00 44.00'],
    );
    expect(draft.lines.single.grossAmountCents, isNull);
  });

  test('repeated descriptions and different sizes cannot borrow evidence', () {
    final draft = compare(
      ['STORE', 'Coffee 1.5L', 'Coffee 26g', 'Coffee 26g'],
      ['STORE', '2 pcs Coffee 15L 44.00', '2 pcs Coffee 26g 44.00'],
    );
    expect(draft.lines, hasLength(3));
    expect(draft.lines.every((line) => line.grossAmountCents == null), isTrue);
  });

  test('owner-edited blank fields and confirmed lines are preserved', () {
    final page = ReceiptOcrPage(
      imagePath: '/source',
      textLines: const [
        OcrTextLine(text: 'STORE'),
        OcrTextLine(text: 'Coffee 26g'),
      ],
      originalTextLines: const [
        OcrTextLine(text: 'STORE'),
        OcrTextLine(text: '2 pcs Coffee 26g 44.00'),
      ],
    );
    final draft = ReceiptParser().parsePages(pages: [page]);
    draft.lines.single
      ..quantityEdited = true
      ..amountEdited = true;
    const ReceiptOcrComparison().supplement(draft, [page]);
    expect(draft.lines.single.quantity, isNull);
    expect(draft.lines.single.grossAmountCents, isNull);
    draft.lines.single
      ..quantityEdited = false
      ..amountEdited = false
      ..confirmed = true;
    const ReceiptOcrComparison().supplement(draft, [page]);
    expect(draft.lines.single.quantity, isNull);
    expect(page.snapshot().originalTextLines.last.text, contains('44.00'));
  });

  test('actual public OCR retains selected rows while comparing originals', () {
    for (final name in ['dali', 'waltermart', 'savemore']) {
      final page = ReceiptOcrPage(
        imagePath: '/$name.jpg',
        textLines: fixture('${name}_enhanced'),
        originalTextLines: fixture(name),
      );
      final draft = ReceiptParser().parsePages(pages: [page]);
      final descriptions = draft.lines.map((line) => line.description).toList();
      final quantitiesBefore = draft.lines
          .where((line) => line.quantity != null)
          .length;
      final amountsBefore = draft.lines
          .where((line) => line.grossAmountCents != null)
          .length;
      const ReceiptOcrComparison().supplement(draft, [page]);
      expect(draft.lines.map((line) => line.description), descriptions);
      final quantitiesAfter = draft.lines
          .where((line) => line.quantity != null)
          .length;
      final amountsAfter = draft.lines
          .where((line) => line.grossAmountCents != null)
          .length;
      expect(quantitiesAfter, greaterThanOrEqualTo(quantitiesBefore));
      expect(amountsAfter, greaterThanOrEqualTo(amountsBefore));
      // Completeness counts are not accuracy measurements against source pixels.
      // ignore: avoid_print
      print(
        '$name: quantities $quantitiesBefore->$quantitiesAfter, amounts $amountsBefore->$amountsAfter',
      );
    }
  });
}

class _ComparisonOcr implements OcrService {
  _ComparisonOcr(this.responses);
  final Map<String, List<OcrTextLine>> responses;
  final calls = <String>[];
  String? failingPath;
  @override
  Future<List<OcrTextLine>> recognize(String imagePath) async {
    calls.add(imagePath);
    if (imagePath == failingPath) throw StateError('comparison failed');
    return responses[imagePath] ?? (throw StateError('unexpected engine/path'));
  }

  @override
  Future<void> close() async {}
}
