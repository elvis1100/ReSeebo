import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/main.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'welcome leads into the existing store and returns on a fresh app',
    (tester) async {
      await tester.pumpWidget(const ReseeboApp());
      await tester.pumpAndSettle();
      expect(find.text('Get started'), findsOneWidget);
      expect(
        find.image(const AssetImage('assets/brand/reseebo_logo.png')),
        findsOneWidget,
      );
      expect(find.text('Scan Receipt'), findsNothing);

      await tester.ensureVisible(find.text('Get started'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(find.text('Get started'), findsNothing);
      expect(find.text('Scan Receipt'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Save settings'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const ReseeboApp());
      await tester.pumpAndSettle();
      expect(find.text('Get started'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [360.0, 412.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'welcome remains usable at ${width}dp and text scale $scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final preview = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(key: preview, child: const ReseeboApp()),
          );
          await tester.pumpAndSettle();
          expect(find.text('Get started'), findsOneWidget);
          await tester.ensureVisible(find.text('Get started'));
          expect(find.text('Get started').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);

          if (const bool.fromEnvironment('BRAND_PREVIEWS') && scale == 1) {
            await tester.runAsync(() async {
              final boundary =
                  preview.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              image.dispose();
              final file = File(
                'build/brand-preview/landing-${width.toInt()}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
            });
          }
          await tester.tap(find.text('Get started'));
          await tester.pumpAndSettle();
          expect(find.text('Home'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('reduced motion exposes the welcome without an animation wait', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(const ReseeboApp());
    expect(find.text('Get started'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.ensureVisible(find.text('Get started'));
    await tester.pump();
    expect(find.text('Get started').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('Scan Receipt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
