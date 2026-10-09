import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reseebo_app/features/receipt_scan/widgets/receipt_photo_comparison.dart';

void main() {
  testWidgets(
    'comparison reveals both versions, keeps zoom aligned, and releases canceled divider drag',
    (tester) async {
      late Directory folder;
      late File original;
      late File enhanced;
      await tester.runAsync(() async {
        folder = await Directory.systemTemp.createTemp('reseebo-compare-test-');
        original = File('${folder.path}/original.png');
        enhanced = File('${folder.path}/enhanced.png');
        for (final entry in [
          (original, img.ColorRgb8(240, 30, 30)),
          (enhanced, img.ColorRgb8(30, 30, 240)),
        ]) {
          final image = img.Image(
            width: 200,
            height: entry.$1 == enhanced ? 200 : 100,
          );
          img.fill(image, color: entry.$2);
          await entry.$1.writeAsBytes(img.encodePng(image));
        }
      });
      addTearDown(() => tester.runAsync(() => folder.delete(recursive: true)));
      final originalBytes = await tester.runAsync(original.readAsBytes);
      final interactions = <bool>[];
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.runAsync(() async {
        for (final file in [original, enhanced]) {
          await precacheImage(
            ResizeImage(FileImage(file), width: 1600),
            tester.element(find.byType(Scaffold)),
          ).timeout(const Duration(seconds: 5));
        }
      });
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: ReceiptPhotoComparison(
                      originalPath: original.path,
                      enhancedPath: enhanced.path,
                      height: 300,
                      onInteractionActiveChanged: interactions.add,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      });
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Enhanced'), findsOneWidget);

      Future<img.Image> pixels() async {
        await tester.pump();
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return img.decodePng(bytes!.buffer.asUint8List())!;
      }

      final before = await tester.runAsync(pixels);
      expect(before!.getPixel(100, 190).r, greaterThan(200));
      expect(before.getPixel(300, 190).b, greaterThan(200));
      // Different aspect ratios must not leak the enhanced image through the
      // preserved original's letterbox margin on the left of the divider.
      expect(before.getPixel(100, 40).r, 15);
      expect(before.getPixel(300, 40).b, greaterThan(200));
      final views = tester
          .widgetList<InteractiveViewer>(find.byType(InteractiveViewer))
          .toList();
      expect(
        views[0].transformationController,
        same(views[1].transformationController),
      );
      final transform = views[0].transformationController!;
      transform.value = Matrix4.identity()
        ..setEntry(0, 0, 2)
        ..setEntry(1, 1, 2);
      await tester.pump();
      final zoomed = await tester.runAsync(pixels);
      expect(zoomed!.getPixel(100, 190).r, greaterThan(200));
      expect(zoomed.getPixel(300, 190).b, greaterThan(200));
      await tester.tap(find.byTooltip('Fit photo to screen'));
      await tester.pumpAndSettle();
      expect(transform.value.getMaxScaleOnAxis(), 1);

      final handle = find.byKey(const ValueKey('receipt-comparison-divider'));
      final drag = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await drag.moveBy(const Offset(-140, 0));
      await tester.pump();
      await drag.cancel();
      await tester.pumpAndSettle();
      final after = await tester.runAsync(pixels);
      expect(after!.getPixel(100, 190).b, greaterThan(200));
      expect(interactions, [true, false]);
      expect(await tester.runAsync(original.readAsBytes), originalBytes);
      expect(tester.takeException(), isNull);
    },
  );
}
