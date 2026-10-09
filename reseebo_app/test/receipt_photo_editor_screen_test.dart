import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/theme/app_theme.dart';
import 'package:reseebo_app/features/receipt_scan/models/capture_page.dart';
import 'package:reseebo_app/features/receipt_scan/models/receipt_photo_edits.dart';
import 'package:reseebo_app/features/receipt_scan/screens/receipt_photo_editor_screen.dart';
import 'package:reseebo_app/features/receipt_scan/services/local_receipt_image_service.dart';
import 'package:reseebo_app/features/receipt_scan/state/receipt_photo_editor_state.dart';
import 'package:reseebo_app/features/receipt_scan/widgets/receipt_image_viewer.dart';
import 'package:reseebo_app/features/receipt_scan/widgets/receipt_photo_comparison.dart';

class DelayedImageService extends LocalReceiptImageService {
  final preview = Completer<String>();

  @override
  Future<String> prepareRecognition(
    String path, {
    bool enhance = true,
    double contrast = 1,
  }) => preview.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
    await loader.load();
  });
  testWidgets(
    'comparison preserves the selected OCR version and compact controls fit larger phone text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final page = CapturePage(originalPath: '/original.jpg')
        ..preparedPath = '/enhanced.jpg'
        ..useOriginal = true;
      final editor = ReceiptPhotoEditorState(page: page);
      addTearDown(editor.dispose);
      ReceiptPhotoEdits? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Open editor'),
                onPressed: () async {
                  result = await Navigator.push<ReceiptPhotoEdits>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReceiptPhotoEditorScreen(
                        page: page,
                        editorState: editor,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      expect(find.text('Edit photo'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('receipt-photo-compare')));
      await tester.pumpAndSettle();
      expect(editor.useOriginal, isTrue);
      final comparison = tester.widget<ReceiptPhotoComparison>(
        find.byType(ReceiptPhotoComparison),
      );
      expect(comparison.originalPath, '/original.jpg');
      expect(comparison.enhancedPath, '/enhanced.jpg');
      final compareBounds = tester.getRect(
        find.byKey(const ValueKey('receipt-photo-compare')),
      );
      final fitBounds = tester.getRect(
        find.widgetWithIcon(IconButton, Icons.fit_screen_rounded),
      );
      expect(compareBounds.overlaps(fitBounds), isFalse);
      expect(compareBounds.height, greaterThanOrEqualTo(48));
      expect(fitBounds.height, greaterThanOrEqualTo(48));
      expect(fitBounds.width, greaterThanOrEqualTo(48));
      expect(find.text('The original photo will be read.'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('receipt-photo-compare')));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptPhotoComparison), findsNothing);
      expect(editor.useOriginal, isTrue);
      final reset = find.widgetWithText(TextButton, 'Reset edits');
      final faded = find.text('Faded text clearer');
      final row = tester.getRect(
        find.byKey(const ValueKey('receipt-photo-enhance-reset-row')),
      );
      expect(row.contains(tester.getCenter(reset)), isTrue);
      expect(row.contains(tester.getCenter(faded)), isTrue);
      expect(row.height, lessThanOrEqualTo(88));
      final fadedParagraph = tester.renderObject<RenderParagraph>(faded);
      final fadedPainter = TextPainter(
        text: fadedParagraph.text,
        textDirection: TextDirection.ltr,
        textScaler: fadedParagraph.textScaler,
      )..layout(maxWidth: fadedParagraph.size.width);
      final lines = fadedPainter.computeLineMetrics();
      fadedPainter.dispose();
      expect(lines.length, lessThanOrEqualTo(3));
      expect(
        lines.every((line) => line.width <= fadedParagraph.size.width + .01),
        isTrue,
      );
      expect(tester.getRect(faded).bottom, lessThanOrEqualTo(row.bottom));
      expect(fadedParagraph.didExceedMaxLines, isFalse);
      final fadedStyle =
          tester.widget<Text>(faded).style ??
          DefaultTextStyle.of(tester.element(faded)).style;
      expect(fadedStyle.fontFamily, 'Inter');
      expect(tester.getRect(reset).right, lessThanOrEqualTo(360));
      expect(tester.getRect(faded).left, greaterThanOrEqualTo(0));
      expect(
        tester.getRect(faded).right,
        lessThanOrEqualTo(tester.getRect(reset).left),
      );
      final resetWidget = tester.widget<TextButton>(reset);
      expect(
        resetWidget.style!.foregroundColor!.resolve({}),
        AppColors.textPrimary,
      );
      expect(resetWidget.style!.side?.resolve({}), isNull);
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(
        appBar.titleTextStyle!.fontSize,
        AppTheme.light.appBarTheme.titleTextStyle!.fontSize,
      );
      expect(
        appBar.titleTextStyle!.fontWeight,
        AppTheme.light.appBarTheme.titleTextStyle!.fontWeight,
      );
      expect(appBar.iconTheme!.color, Colors.white);
      expect(appBar.titleTextStyle!.fontFamily, 'Inter');
      final backIcon = find.descendant(
        of: find.widgetWithIcon(IconButton, Icons.arrow_back_rounded),
        matching: find.byType(Icon),
      );
      expect(IconTheme.of(tester.element(backIcon)).color, Colors.white);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.arrow_back_rounded),
            )
            .color,
        Colors.white,
      );
      await tester.tap(find.widgetWithIcon(IconButton, Icons.check_rounded));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.useOriginal, isTrue);
      expect(page.useOriginal, isTrue);
      expect(find.text('Open editor'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('preparing a preview disables editing, submit and route back', (
    tester,
  ) async {
    final page = CapturePage(originalPath: '/original.jpg');
    final images = DelayedImageService();
    final editor = ReceiptPhotoEditorState(page: page, imageService: images);
    addTearDown(editor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ReceiptPhotoEditorScreen(page: page, editorState: editor),
      ),
    );
    expect(editor.busy, isTrue);
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
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.check_rounded),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Rotate'))
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
    images.preview.complete('/enhanced.jpg');
    await tester.pumpAndSettle();
    expect(editor.busy, isFalse);
    expect(
      tester
          .widget<PopScope>(
            find.byWidgetPredicate((widget) => widget is PopScope),
          )
          .canPop,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'photo interaction disables editing controls without swallowing its release',
    (tester) async {
      final page = CapturePage(originalPath: '/original.jpg')
        ..preparedPath = '/enhanced.jpg';
      final editor = ReceiptPhotoEditorState(page: page);
      addTearDown(editor.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ReceiptPhotoEditorScreen(page: page, editorState: editor),
        ),
      );
      final photo = tester.widget<ReceiptImageViewer>(
        find.byType(ReceiptImageViewer),
      );
      photo.onInteractionActiveChanged!(true);
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.check_rounded),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<Switch>(find.byKey(const ValueKey('receipt-faded-text')))
            .onChanged,
        isNull,
      );
      final absorber = tester.widget<AbsorbPointer>(
        find
            .ancestor(
              of: find.byType(ReceiptImageViewer),
              matching: find.byType(AbsorbPointer),
            )
            .first,
      );
      expect(absorber.absorbing, isFalse);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('receipt-photo-compare')),
            )
            .onPressed,
        isNull,
      );
      photo.onInteractionActiveChanged!(false);
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.check_rounded),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<Switch>(find.byKey(const ValueKey('receipt-faded-text')))
            .onChanged,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'header Cancel discards the selected version instead of committing it',
    (tester) async {
      final page = CapturePage(originalPath: '/original.jpg')
        ..preparedPath = '/enhanced.jpg';
      final editor = ReceiptPhotoEditorState(page: page);
      addTearDown(editor.dispose);
      var closed = false;
      ReceiptPhotoEdits? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Open editor'),
                onPressed: () async {
                  result = await Navigator.push<ReceiptPhotoEdits>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReceiptPhotoEditorScreen(
                        page: page,
                        editorState: editor,
                      ),
                    ),
                  );
                  closed = true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      editor.selectOriginal(true);
      await tester.pump();
      expect(editor.useOriginal, isTrue);
      expect(find.widgetWithText(TextButton, 'Reset edits'), findsOneWidget);
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.arrow_back_rounded),
      );
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isNull);
      expect(page.useOriginal, isFalse);
      expect(page.recognitionPath, isNull);
      expect(page.preparedPath, '/enhanced.jpg');
      expect(tester.takeException(), isNull);
    },
  );
}
