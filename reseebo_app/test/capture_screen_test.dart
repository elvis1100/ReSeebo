import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/features/receipt_scan/screens/capture_screen.dart';

void main() {
  testWidgets(
    'active capture screen offers real capture and reports preparation before reading',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: CaptureScreen(dataAdapter: MockReseeboDataAdapter())),
      );
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Read receipt'), findsOneWidget);
      expect(find.textContaining('offline'), findsWidgets);
      final readButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Read receipt'),
      );
      expect(readButton.onPressed, isNull);
      expect(find.text('Try Demo Receipt'), findsNothing);
    },
  );
}
