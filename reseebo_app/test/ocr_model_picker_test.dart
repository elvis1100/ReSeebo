import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/models/ocr_engine.dart';
import 'package:reseebo_app/features/receipt_scan/screens/capture_screen.dart';

import 'fixtures/receipt_scan_widget_fixture.dart';

void main() {
  testWidgets(
    'canceling photo editor after discard approval keeps returned owner edits',
    (tester) async {
      final adapter = ScanWidgetAdapter();
      final state = await fixtureCapture(tester, adapter);
      var reviews = 0;
      await tester.pumpWidget(
        scanApp(
          CaptureScreen(
            dataAdapter: adapter,
            captureState: state,
            onReviewRequested: (draft) async {
              if (reviews++ == 0) {
                draft.lines.single.description = 'Owner coffee';
              } else {
                expect(draft.lines.single.description, 'Owner coffee');
              }
              return draft;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await finishRead(tester);
      await tapCaptureAction(tester, find.text('Review details'));
      await revealCaptureBody(tester, find.text('Edit / enhance photo'));
      await tester.tap(find.text('Edit / enhance photo'));
      await tester.pumpAndSettle();
      await tapCaptureAction(tester, find.text('Discard edits'));
      await tester.tap(find.byTooltip('Cancel edits'));
      await tester.pumpAndSettle();
      await tapCaptureAction(tester, find.text('Review details'));
      await tapCaptureAction(tester, find.text('Save Needs review'));
      expect(
        adapter.pendingDrafts.single.lines.single.description,
        'Owner coffee',
      );
      expect(adapter.reads, [OcrEngineId.mlKit]);
      expect(
        state.selectedDraftSnapshot().lines.single.description,
        'mlKit Coffee',
      );
    },
  );

  testWidgets(
    'approved replacement discards returned edits before explicitly reading a new model',
    (tester) async {
      final adapter = ScanWidgetAdapter();
      final state = await fixtureCapture(tester, adapter);
      await tester.pumpWidget(
        scanApp(
          CaptureScreen(
            dataAdapter: adapter,
            captureState: state,
            onReviewRequested: (draft) async {
              draft.lines.single.description = 'Owner coffee';
              return draft;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await finishRead(tester);
      await tapCaptureAction(tester, find.text('Review details'));
      await revealCaptureBody(tester, find.text('ML Kit Latin'));
      await tapCaptureAction(tester, find.text('ML Kit Latin'));
      await tapCaptureAction(tester, find.text('PP-OCRv5 Mobile'));
      await tapCaptureAction(tester, find.text('Discard edits'));
      expect(adapter.reads, [OcrEngineId.mlKit]);
      await finishRead(tester);
      await tapCaptureAction(tester, find.text('Save Needs review'));
      expect(
        adapter.pendingDrafts.single.lines.single.description,
        'ppOcrV5Mobile Coffee',
      );
      expect(adapter.reads, [OcrEngineId.mlKit, OcrEngineId.ppOcrV5Mobile]);
    },
  );
  testWidgets(
    'canceling the photo picker after discard approval retains edits and cache',
    (tester) async {
      final adapter = ScanWidgetAdapter();
      final picker = CancelScanPicker();
      final state = await fixtureCapture(tester, adapter, picker: picker);
      var reviews = 0;
      await tester.pumpWidget(
        scanApp(
          CaptureScreen(
            dataAdapter: adapter,
            captureState: state,
            onReviewRequested: (draft) async {
              if (reviews++ == 0) {
                draft.lines.single.description = 'Owner coffee';
              } else {
                expect(draft.lines.single.description, 'Owner coffee');
              }
              return draft;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await finishRead(tester);
      await tapCaptureAction(tester, find.text('Review details'));
      await revealCaptureBody(tester, find.text('Add photos'));
      await tapCaptureAction(tester, find.text('Add photos'));
      await tapCaptureAction(tester, find.text('Discard edits'));
      expect(picker.picks, 1);
      await tapCaptureAction(tester, find.text('Review details'));
      expect(
        state.selectedDraftSnapshot().lines.single.description,
        'mlKit Coffee',
      );
      expect(adapter.reads, [OcrEngineId.mlKit]);
    },
  );

  testWidgets(
    'returning owner edits survive canceling replacement and saving',
    (tester) async {
      final adapter = ScanWidgetAdapter();
      final state = await fixtureCapture(tester, adapter);
      var reviews = 0;
      await tester.pumpWidget(
        scanApp(
          CaptureScreen(
            dataAdapter: adapter,
            captureState: state,
            onReviewRequested: (draft) async {
              reviews++;
              if (reviews == 1) {
                draft.lines.single.description = 'Owner edited coffee';
                draft.lines.single.provenance[ReceiptSuggestionField
                    .description] = const ReceiptFieldProvenance(
                  origin: ReceiptFieldOrigin.ownerEdited,
                  explanation: 'Owner entered description.',
                );
              } else {
                expect(draft.lines.single.description, 'Owner edited coffee');
              }
              return draft;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await finishRead(tester);
      await tapCaptureAction(tester, find.text('Review details'));
      await revealCaptureBody(tester, find.text('ML Kit Latin'));
      await tapCaptureAction(tester, find.text('ML Kit Latin'));
      await tapCaptureAction(tester, find.text('PP-OCRv5 Mobile'));
      expect(find.text('Replace your review edits?'), findsOneWidget);
      await tester.tap(find.text('Keep edits'));
      await tester.pumpAndSettle();
      expect(state.selectedEngineId, OcrEngineId.mlKit);
      await tapCaptureAction(tester, find.text('Review details'));
      await tapCaptureAction(tester, find.text('Save Needs review'));
      expect(
        adapter.pendingDrafts.single.lines.single.description,
        'Owner edited coffee',
      );
      expect(
        state.selectedDraftSnapshot().lines.single.description,
        'mlKit Coffee',
      );
      expect(adapter.reads, [OcrEngineId.mlKit]);
    },
  );

  testWidgets(
    'external image changes refuse saving a retained review snapshot',
    (tester) async {
      final adapter = ScanWidgetAdapter();
      final state = await fixtureCapture(tester, adapter);
      await tester.pumpWidget(
        scanApp(
          CaptureScreen(
            dataAdapter: adapter,
            captureState: state,
            onReviewRequested: (draft) async {
              draft.lines.single.description = 'Owner edited coffee';
              return draft;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await finishRead(tester);
      await tapCaptureAction(tester, find.text('Review details'));
      await tester.runAsync(
        () => File(state.pages.single.originalPath).writeAsBytes([1, 2, 3, 4]),
      );
      await tapCaptureAction(tester, find.text('Save Needs review'));
      expect(adapter.pendingDrafts, isEmpty);
      await revealCaptureBody(tester, find.textContaining('photos changed'));
      expect(find.textContaining('photos changed'), findsWidgets);
    },
  );

  testWidgets(
    'a failed selected model retries only after the explicit action',
    (tester) async {
      final adapter = ScanWidgetAdapter()..failReading = true;
      final state = await fixtureCapture(tester, adapter);
      await tester.pumpWidget(
        scanApp(CaptureScreen(dataAdapter: adapter, captureState: state)),
      );
      await tester.pumpAndSettle();
      await finishRead(tester);
      expect(find.text('Retry reading'), findsOneWidget);
      expect(adapter.reads, [OcrEngineId.mlKit]);
      adapter.failReading = false;
      await finishRead(tester, label: 'Retry reading');
      expect(adapter.reads, [OcrEngineId.mlKit, OcrEngineId.mlKit]);
      expect(find.text('Review details'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selector starts with ML Kit and changing a model requires explicit Read',
    (tester) async {
      final adapter = ScanWidgetAdapter();
      final state = await fixtureCapture(tester, adapter);
      await tester.pumpWidget(
        scanApp(CaptureScreen(dataAdapter: adapter, captureState: state)),
      );
      await tester.pumpAndSettle();
      await revealCaptureBody(tester, find.text('ML Kit Latin'));
      await tapCaptureAction(tester, find.text('ML Kit Latin'));
      expect(find.text('PP-OCRv5 Mobile'), findsOneWidget);
      expect(find.text('PP-OCRv6 Medium'), findsOneWidget);
      await tapCaptureAction(tester, find.text('PP-OCRv5 Mobile'));
      expect(state.selectedEngineId, OcrEngineId.ppOcrV5Mobile);
      expect(adapter.reads, isEmpty);
      await finishRead(tester);
      expect(adapter.reads, [OcrEngineId.ppOcrV5Mobile]);
      expect(find.text('Review details'), findsOneWidget);
    },
  );

  testWidgets(
    'reading keeps Photos open and Review receives only selected cached result',
    (tester) async {
      final adapter = ScanWidgetAdapter();
      final state = await fixtureCapture(tester, adapter);
      ReceiptDraft? received;
      await tester.pumpWidget(
        scanApp(
          CaptureScreen(
            dataAdapter: adapter,
            captureState: state,
            onDraftReady: (draft) => received = draft,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await finishRead(tester);
      expect(received, isNull);
      await tapCaptureAction(tester, find.text('Review details'));
      expect(received!.lines.single.description, 'mlKit Coffee');
      received!.lines.single.description = 'Owner coffee';
      expect(
        state.selectedDraftSnapshot().lines.single.description,
        'mlKit Coffee',
      );
      await revealCaptureBody(tester, find.text('ML Kit Latin'));
      await tapCaptureAction(tester, find.text('ML Kit Latin'));
      await tapCaptureAction(tester, find.text('PP-OCRv5 Mobile'));
      await finishRead(tester);
      await revealCaptureBody(tester, find.text('PP-OCRv5 Mobile'));
      await tapCaptureAction(tester, find.text('PP-OCRv5 Mobile'));
      await tapCaptureAction(tester, find.text('ML Kit Latin'));
      await tapCaptureAction(tester, find.text('Review details'));
      expect(received!.lines.single.description, 'mlKit Coffee');
      expect(adapter.reads, [OcrEngineId.mlKit, OcrEngineId.ppOcrV5Mobile]);
    },
  );

  testWidgets('unverified Paddle models remain visible and disabled', (
    tester,
  ) async {
    final adapter = ScanWidgetAdapter()
      ..descriptors = [
        scanEngines.first,
        for (final model in scanEngines.skip(1))
          OcrEngineDescriptor(
            id: model.id,
            label: model.label,
            modelVersion: model.modelVersion,
            runtimeVersion: model.runtimeVersion,
            available: false,
            unavailableReason:
                'Samsung API 36 OpenCV load failed (__sfp_handle_exceptions).',
          ),
      ];
    final state = await fixtureCapture(tester, adapter);
    await tester.pumpWidget(
      scanApp(CaptureScreen(dataAdapter: adapter, captureState: state)),
    );
    await tester.pumpAndSettle();
    await revealCaptureBody(tester, find.text('ML Kit Latin'));
    await tapCaptureAction(tester, find.text('ML Kit Latin'));
    await tapCaptureAction(tester, find.text('PP-OCRv6 Medium'));
    expect(state.selectedEngineId, OcrEngineId.mlKit);
    expect(adapter.reads, isEmpty);
    expect(
      find.text('Unavailable in this version. Use ML Kit Latin.'),
      findsNWidgets(2),
    );
    expect(find.textContaining('__sfp_handle_exceptions'), findsNothing);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(2));
  });

  for (final width in [360.0, 412.0]) {
    testWidgets(
      'long failure and unavailable-model explanation fit ${width.toInt()}dp at scale 2',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final adapter = ScanWidgetAdapter()
          ..failReading = true
          ..descriptors = [
            scanEngines.first,
            for (final engine in scanEngines.skip(1))
              OcrEngineDescriptor(
                id: engine.id,
                label: engine.label,
                modelVersion: engine.modelVersion,
                runtimeVersion: engine.runtimeVersion,
                available: false,
                unavailableReason:
                    'Device verification pending. This bundled model remains disabled until offline recognition has been verified on the owner’s phone.',
              ),
          ];
        final state = await fixtureCapture(tester, adapter);
        await tester.pumpWidget(
          scanApp(
            CaptureScreen(dataAdapter: adapter, captureState: state),
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        await finishRead(tester);
        await revealCaptureBody(
          tester,
          find.textContaining('The selected model could not read every word'),
        );
        expect(find.text('Retry reading').hitTestable(), findsOneWidget);
        expect(
          find.text('Save photos for later').hitTestable(),
          findsOneWidget,
        );
        await revealCaptureBody(tester, find.text('ML Kit Latin'));
        await tapCaptureAction(tester, find.text('ML Kit Latin'));
        await tester.scrollUntilVisible(
          find.text('PP-OCRv6 Medium'),
          160,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tapCaptureAction(tester, find.text('PP-OCRv6 Medium'));
        expect(state.selectedEngineId, OcrEngineId.mlKit);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'selector and raw text remain reachable at ${width.toInt()}dp and scale 2',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final adapter = ScanWidgetAdapter();
        final state = await fixtureCapture(tester, adapter);
        await tester.pumpWidget(
          scanApp(
            CaptureScreen(dataAdapter: adapter, captureState: state),
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        await revealCaptureBody(tester, find.text('ML Kit Latin'));
        await tapCaptureAction(tester, find.text('ML Kit Latin'));
        await tester.scrollUntilVisible(
          find.text('PP-OCRv6 Medium'),
          160,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tapCaptureAction(tester, find.text('PP-OCRv6 Medium'));
        await finishRead(tester);
        await revealCaptureBody(tester, find.text('Raw recognized text'));
        await tester.tap(find.text('Raw recognized text'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Coffee 2 42.00'), findsOneWidget);
        expect(find.text('Save Needs review').hitTestable(), findsOneWidget);
        expect(find.text('Review details').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
