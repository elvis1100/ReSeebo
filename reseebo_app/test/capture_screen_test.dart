import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/theme/app_theme.dart';
import 'package:reseebo_app/features/receipt_scan/screens/capture_screen.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/features/receipt_scan/models/receipt_image_quality.dart';
import 'package:reseebo_app/features/receipt_scan/services/local_receipt_image_service.dart';
import 'package:reseebo_app/features/receipt_scan/state/capture_state.dart';
import 'package:reseebo_app/features/receipt_scan/widgets/receipt_image_viewer.dart';

class DelayedCaptureAdapter extends MockReseeboDataAdapter {
  final release = Completer<void>();

  @override
  Future<ReceiptDraft> processReceiptImages(
    List<String> localImagePaths, {
    List<String>? recognitionImagePaths,
  }) async {
    await release.future;
    return ReceiptDraft(imagePath: localImagePaths.first);
  }
}

class TestCaptureImages extends LocalReceiptImageService {
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
  }) async => '/enhanced.jpg';
}

void main() {
  testWidgets(
    'staggered photo pinch zooms without page drift and releases scrolling after cancel',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final adapter = MockReseeboDataAdapter();
      final state = CaptureState(
        adapter: adapter,
        initialImagePath: '/original.jpg',
      );
      state.selectedPage!.preparedPath = '/enhanced.jpg';
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: CaptureScreen(dataAdapter: adapter, captureState: state),
        ),
      );
      await tester.ensureVisible(find.byType(ReceiptImageViewer));
      await tester.pumpAndSettle();
      expect(find.text('Enhanced'), findsOneWidget);
      final photo = tester.getRect(find.byType(InteractiveViewer));
      expect(
        tester.getRect(find.text('Enhanced')).center.dx,
        greaterThan(photo.center.dx),
      );
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final offset = scroll.position.pixels;
      final transform = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      final first = await tester.createGesture(pointer: 1);
      final second = await tester.createGesture(pointer: 2);
      final center = photo.center;
      await first.down(center - const Offset(30, 0));
      await tester.pump();
      expect(
        tester.widget<ListView>(find.byType(ListView)).physics,
        isA<NeverScrollableScrollPhysics>(),
      );
      // The first finger drifts vertically before the second one lands. This
      // previously let the page's drag recognizer win instead of photo scaling.
      await first.moveTo(center + const Offset(-30, 35));
      await tester.pump();
      await second.down(center + const Offset(30, 35));
      await tester.pump();
      await first.moveTo(center + const Offset(-85, 50));
      await second.moveTo(center + const Offset(85, 20));
      await tester.pump();
      expect(transform.value.getMaxScaleOnAxis(), greaterThan(1.5));
      expect(scroll.position.pixels, closeTo(offset, .01));
      await first.up();
      await tester.pump();
      expect(
        tester.widget<ListView>(find.byType(ListView)).physics,
        isA<NeverScrollableScrollPhysics>(),
      );
      await second.cancel();
      await tester.pumpAndSettle();
      expect(
        tester.widget<ListView>(find.byType(ListView)).physics,
        isNot(isA<NeverScrollableScrollPhysics>()),
      );
      await tester.tap(find.byTooltip('Fit photo to screen'));
      await tester.pumpAndSettle();
      expect(transform.value.getMaxScaleOnAxis(), 1);
      await tester.dragFrom(Offset(4, photo.center.dy), const Offset(0, -70));
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(offset));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'active capture screen offers real capture and reports preparation before reading',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: CaptureScreen(dataAdapter: MockReseeboDataAdapter())),
      );
      expect(find.text('Take photo'), findsOneWidget);
      expect(find.text('Choose photos'), findsOneWidget);
      expect(find.text('Read receipt'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.textContaining('Works offline'), findsNothing);
      final readButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Read receipt'),
      );
      expect(readButton.onPressed, isNull);
      expect(find.text('Try Demo Receipt'), findsNothing);
    },
  );
  testWidgets('capture guidance fits a narrow phone with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: CaptureScreen(dataAdapter: MockReseeboDataAdapter()),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Read receipt').hitTestable(), findsOneWidget);
  });
  testWidgets(
    'reading disables competing controls and system-back navigation',
    (tester) async {
      final adapter = DelayedCaptureAdapter();
      final state = CaptureState(
        adapter: adapter,
        initialImagePath: '/original.jpg',
        imageService: TestCaptureImages(),
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Start scan'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CaptureScreen(
                      dataAdapter: adapter,
                      captureState: state,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start scan'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Edit / enhance photo'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Read receipt'));
      await tester.pump();
      expect(state.busy, isTrue);
      expect(
        tester
            .widget<PopScope>(
              find.byWidgetPredicate((widget) => widget is PopScope),
            )
            .canPop,
        isFalse,
      );
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Read receipt'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Edit / enhance photo'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.arrow_back_rounded),
            )
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(CaptureScreen), findsOneWidget);
      adapter.release.complete();
      await tester.pumpAndSettle();
      expect(state.busy, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
