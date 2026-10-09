import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/features/receipt_scan/widgets/receipt_image_geometry.dart';
import 'package:reseebo_app/features/receipt_scan/widgets/receipt_image_viewer.dart';

void main() {
  testWidgets(
    'encoded dimensions align tokens and preserve tap selection after zoom',
    (tester) async {
      late Directory folder;
      late File file;
      await tester.runAsync(() async {
        folder = await Directory.systemTemp.createTemp('reseebo-overlay-test-');
        file = File('${folder.path}/receipt.png');
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.white, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(200, 100);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      });
      addTearDown(() => tester.runAsync(() => folder.delete(recursive: true)));
      int? selected;
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      // Load the display image in the real async zone before the viewer starts,
      // so precaching never waits on an image task pending in the fake zone.
      await tester.runAsync(
        () => precacheImage(
          FileImage(file),
          tester.element(find.byType(Scaffold)),
        ).timeout(const Duration(seconds: 5)),
      );
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 100,
                  child: ReceiptImageViewer(
                    imagePath: file.path,
                    height: 100,
                    tokens: const [
                      OcrTextToken(
                        text: '12',
                        left: 100,
                        top: 0,
                        width: 100,
                        height: 100,
                      ),
                    ],
                    onTokenSelected: (index) => selected = index,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      });
      final token = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Select receipt text 12',
      );
      await tester.runAsync(() async {
        for (
          var attempt = 0;
          attempt < 100 && token.evaluate().isEmpty;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      expect(token, findsOneWidget);
      final scene = tester.getRect(find.byType(InteractiveViewer));
      // The 1dp border leaves a 98x98 scene. A 200x100 receipt is fitted at .49.
      expect(
        tester.getRect(token),
        Rect.fromLTWH(scene.left + 49, scene.top + 24.5, 49, 49),
      );
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      viewer.transformationController!.value = Matrix4.identity()
        ..setEntry(0, 0, 2)
        ..setEntry(1, 1, 2)
        ..setEntry(0, 3, -50)
        ..setEntry(1, 3, -25);
      await tester.pump();
      await tester.tapAt(scene.topLeft + const Offset(70, 50));
      expect(selected, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await FileImage(file).evict();
    },
  );
  test(
    'contain mapping includes letterbox offset rather than stretching bounds',
    () {
      expect(
        fitReceiptBounds(
          const Rect.fromLTWH(100, 0, 100, 100),
          imageSize: const Size(200, 100),
          viewport: const Size(100, 100),
        ),
        const Rect.fromLTWH(50, 25, 50, 50),
      );
      expect(
        fitReceiptBounds(
          const Rect.fromLTWH(0, 100, 100, 100),
          imageSize: const Size(100, 200),
          viewport: const Size(100, 100),
        ),
        const Rect.fromLTWH(25, 50, 50, 50),
      );
    },
  );
}
