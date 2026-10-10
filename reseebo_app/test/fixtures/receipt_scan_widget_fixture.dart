import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/models/pending_receipt.dart';
import 'package:reseebo_app/core/models/ocr_engine.dart';
import 'package:reseebo_app/core/errors/app_exception.dart';
import 'package:reseebo_app/core/theme/app_theme.dart';
import 'package:reseebo_app/features/receipt_scan/models/receipt_image_quality.dart';
import 'package:reseebo_app/features/receipt_scan/services/local_receipt_image_service.dart';
import 'package:reseebo_app/features/receipt_scan/state/capture_state.dart';
import 'package:reseebo_app/features/receipt_scan/screens/capture_screen.dart';

const scanEngines = <OcrEngineDescriptor>[
  OcrEngineDescriptor(
    id: OcrEngineId.mlKit,
    label: 'ML Kit Latin',
    modelVersion: 'fixture-1',
    runtimeVersion: 'fixture-1',
    available: true,
  ),
  OcrEngineDescriptor(
    id: OcrEngineId.ppOcrV5Mobile,
    label: 'PP-OCRv5 Mobile',
    modelVersion: 'fixture-5',
    runtimeVersion: 'fixture-1',
    available: true,
  ),
  OcrEngineDescriptor(
    id: OcrEngineId.ppOcrV6Medium,
    label: 'PP-OCRv6 Medium',
    modelVersion: 'fixture-6',
    runtimeVersion: 'fixture-1',
    available: true,
  ),
];

class ScanWidgetAdapter extends MockReseeboDataAdapter {
  List<OcrEngineDescriptor> descriptors = scanEngines;
  final reads = <OcrEngineId>[];
  final pendingCommands = <String>[];
  final pendingDrafts = <ReceiptDraft>[];
  final pendingTargets = <String?>[];
  final pendingRevisions = <int?>[];
  bool failReading = false;
  int confirmedWrites = 0;
  bool noLines = false;
  bool failSavingOnce = false;
  Completer<void>? saveBarrier;

  @override
  Future<List<OcrEngineDescriptor>> getOcrEngines() async => descriptors;

  @override
  Future<List<Product>> getProducts({String? query}) async => const [];
  @override
  Future<List<Supplier>> getSuppliers() async => const [];
  @override
  Future<List<ProductMatchSuggestion>> matchAliases(
    String description, {
    String? supplierId,
  }) async => const [];

  @override
  Future<SaveReceiptResult> saveConfirmedReceipt(ReceiptDraft draft) async {
    confirmedWrites++;
    return super.saveConfirmedReceipt(draft);
  }

  @override
  Future<ReceiptDraft> processReceiptImages(
    List<String> localImagePaths, {
    List<String>? recognitionImagePaths,
    List<String>? comparisonImagePaths,
    OcrEngineId engineId = OcrEngineId.mlKit,
    String preprocessingRevision = '1',
  }) async {
    reads.add(engineId);
    if (failReading) {
      throw const AppException(
        'The selected model could not read every word on this long receipt. Please check the original photo, retry reading, or save photos for later.',
      );
    }
    return ReceiptDraft(
      imagePath: localImagePaths.first,
      imagePaths: localImagePaths,
      textLines: const [
        OcrTextLine(
          text: 'Coffee 2 42.00',
          left: 0,
          top: 0,
          width: 100,
          height: 20,
        ),
      ],
      lines: noLines
          ? []
          : [
              ParsedLineItem(
                description: '${engineId.name} Coffee',
                quantity: 2,
                unit: PurchaseUnit.piece,
                piecesPerPack: 1,
                grossAmountCents: 4200,
              ),
            ],
    );
  }

  @override
  Future<PendingSaveResult> savePendingReceipt(
    ReceiptDraft draft, {
    required String operationId,
    String? pendingId,
    int? expectedRevision,
    String? correctionOfReceiptId,
    int? expectedConfirmedRevision,
  }) async {
    pendingCommands.add(operationId);
    pendingDrafts.add(draft.snapshot());
    pendingTargets.add(pendingId);
    pendingRevisions.add(expectedRevision);
    if (saveBarrier != null) await saveBarrier!.future;
    if (failSavingOnce) {
      failSavingOnce = false;
      throw StateError('Temporary local save failure');
    }
    return PendingSaveResult(
      id: pendingId ?? 'pending-saved',
      revision: (expectedRevision ?? 0) + 1,
    );
  }
}

class FixtureScanImages extends LocalReceiptImageService {
  @override
  Future<ReceiptImageQuality> inspectQuality(String path) async =>
      const ReceiptImageQuality(
        width: 600,
        height: 800,
        sharpness: 100,
        contrast: 100,
      );

  @override
  Future<String> prepareRecognition(
    String path, {
    bool enhance = true,
    double contrast = 1,
  }) async => path;
}

class CancelScanPicker extends ImagePicker {
  int picks = 0;
  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    picks++;
    return [];
  }
}

Future<CaptureState> fixtureCapture(
  WidgetTester tester,
  ScanWidgetAdapter adapter, {
  ImagePicker? picker,
}) async {
  late Directory directory;
  late File receipt;
  late CaptureState state;
  await tester.runAsync(() async {
    directory = await Directory.systemTemp.createTemp('reseebo-selector-');
    receipt = File('${directory.path}/original.png');
    final pixels = image.Image(width: 600, height: 800);
    image.fill(pixels, color: image.ColorRgb8(245, 245, 245));
    await receipt.writeAsBytes(image.encodePng(pixels));
    state = CaptureState(
      adapter: adapter,
      initialImagePath: receipt.path,
      imageService: FixtureScanImages(),
      picker: picker,
    );
    await Future<void>.delayed(Duration.zero);
  });
  addTearDown(() async {
    state.dispose();
    await tester.runAsync(() => directory.delete(recursive: true));
  });
  return state;
}

Widget scanApp(Widget home, {double scale = 1}) => MaterialApp(
  theme: AppTheme.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: home,
);

Future<void> finishRead(
  WidgetTester tester, {
  String label = 'Read receipt',
}) async {
  await tapCaptureAction(tester, find.text(label));
  final state = tester
      .widget<CaptureScreen>(find.byType(CaptureScreen))
      .captureState!;
  expect(
    state.busy,
    isFalse,
    reason:
        'The real fixture file reads must finish before settling animations.',
  );
}

/// File-backed capture actions run in the real async zone. Footer buttons are
/// always mounted; body controls need scrolling through the lazy list first.
Future<void> tapCaptureAction(WidgetTester tester, Finder target) async {
  await tester.runAsync(() async {
    await tester.tap(target);
  });
  await settleCaptureAction(tester);
}

Future<void> settleCaptureAction(WidgetTester tester) async {
  for (var i = 0; i < 500; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 300));
      if (find.byType(AlertDialog).evaluate().isNotEmpty) return;
    }
    final capture = find.descendant(
      of: find.byType(CaptureScreen),
      matching: find.byType(AbsorbPointer),
    );
    if (capture.evaluate().isEmpty ||
        !tester.widget<AbsorbPointer>(capture.first).absorbing) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

Future<void> revealCaptureBody(WidgetTester tester, Finder target) async {
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(
    target,
    160,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}
