import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/theme/app_theme.dart';
import 'package:reseebo_app/features/receipt_scan/models/capture_page.dart';
import 'package:reseebo_app/features/receipt_scan/models/receipt_photo_edits.dart';
import 'package:reseebo_app/features/receipt_scan/screens/receipt_photo_editor_screen.dart';
import 'package:reseebo_app/features/receipt_scan/services/local_receipt_image_service.dart';
import 'package:reseebo_app/features/receipt_scan/state/receipt_photo_editor_state.dart';
import 'package:reseebo_app/features/receipt_scan/widgets/receipt_image_viewer.dart';

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
  testWidgets(
    'full-screen editor applies the selected original version and fits larger phone text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final page = CapturePage(originalPath: '/original.jpg')
        ..preparedPath = '/enhanced.jpg';
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
      await tester.tap(find.byKey(const ValueKey('receipt-photo-enhancement')));
      await tester.pumpAndSettle();
      expect(editor.useOriginal, isTrue);
      expect(find.text('The original photo will be read.'), findsNothing);
      await tester.tap(find.widgetWithIcon(IconButton, Icons.check_rounded));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.useOriginal, isTrue);
      expect(page.useOriginal, isFalse);
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
            .widget<Switch>(
              find.byKey(const ValueKey('receipt-photo-enhancement')),
            )
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
            .widget<Switch>(
              find.byKey(const ValueKey('receipt-photo-enhancement')),
            )
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
      await tester.tap(find.byKey(const ValueKey('receipt-photo-enhancement')));
      await tester.pump();
      expect(editor.useOriginal, isTrue);
      expect(
        find.widgetWithText(OutlinedButton, 'Reset edits'),
        findsOneWidget,
      );
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
