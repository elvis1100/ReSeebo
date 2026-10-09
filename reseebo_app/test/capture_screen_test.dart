import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/theme/app_theme.dart';
import 'package:reseebo_app/features/receipt_scan/screens/capture_screen.dart';

void main() {
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
      expect(find.textContaining('offline'), findsWidgets);
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
}
