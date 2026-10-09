import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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
    'one-finger preview drag scrolls the page and enhanced badge follows the shown version',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Directory directory;
      late File original;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'reseebo-preview-gesture-',
        );
        original = File('${directory.path}/receipt.png');
        final image = img.Image(width: 600, height: 1000);
        img.fill(image, color: img.ColorRgb8(245, 245, 245));
        await original.writeAsBytes(img.encodePng(image));
      });
      addTearDown(
        () => tester.runAsync(() => directory.delete(recursive: true)),
      );
      final adapter = MockReseeboDataAdapter();
      final state = CaptureState(
        adapter: adapter,
        initialImagePath: original.path,
      );
      state.selectedPage!.preparedPath = original.path;
      addTearDown(state.dispose);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const Scaffold()));
      await tester.runAsync(
        () => precacheImage(
          ResizeImage(FileImage(original), width: 1000),
          tester.element(find.byType(Scaffold)),
        ).timeout(const Duration(seconds: 5)),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: CaptureScreen(dataAdapter: adapter, captureState: state),
        ),
      );
      await tester.ensureVisible(find.byType(ReceiptImageViewer));
      await tester.pumpAndSettle();
      final photo = tester.getRect(find.byType(InteractiveViewer));
      expect(find.text('Enhanced'), findsOneWidget);
      expect(
        tester.getRect(find.text('Enhanced')).center.dx,
        greaterThan(photo.center.dx),
      );
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final offset = scroll.position.pixels;
      await tester.dragFrom(photo.center, const Offset(0, 90));
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, lessThan(offset));
      final pinchOffset = scroll.position.pixels;
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final center = tester.getCenter(find.byType(InteractiveViewer));
      final first = await tester.startGesture(
        center - const Offset(30, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(30, 0),
        pointer: 2,
      );
      await first.moveBy(const Offset(-20, 0));
      await second.moveBy(const Offset(20, 0));
      await tester.pump();
      await first.moveBy(const Offset(-40, 0));
      await second.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(
        viewer.transformationController!.value.getMaxScaleOnAxis(),
        greaterThan(1.5),
      );
      expect(scroll.position.pixels, closeTo(pinchOffset, .01));
      await first.up();
      await second.cancel();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Fit photo to screen'));
      await tester.pumpAndSettle();
      expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
      expect(
        tester.widget<ListView>(find.byType(ListView)).physics,
        isNot(isA<NeverScrollableScrollPhysics>()),
      );
      final remove = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Remove photo'),
      );
      expect(remove.style!.foregroundColor!.resolve({}), AppColors.danger);
      state.selectedPage!.useOriginal = true;
      state.selectPage(0);
      await tester.pump();
      expect(find.text('Enhanced'), findsNothing);
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
