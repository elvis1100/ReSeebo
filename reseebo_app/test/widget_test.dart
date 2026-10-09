import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo/main.dart';

void main() {
  testWidgets('ReseeboApp boots and renders offline dashboard', (WidgetTester tester) async {
    // Build Reseebo and trigger a frame.
    await tester.pumpWidget(const ReseeboApp());
    await tester.pumpAndSettle();

    // Verify that the title and core dashboard controls are rendered.
    expect(find.text('Reseebo'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);
  });
}
