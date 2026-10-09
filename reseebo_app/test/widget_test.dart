import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/main.dart';

void main() {
  testWidgets('ReseeboApp boots and renders offline dashboard', (WidgetTester tester) async {
    // Build Reseebo and trigger a frame.
    await tester.pumpWidget(const ReseeboApp());
    await tester.pumpAndSettle();

    // Verify that the title and core dashboard controls are rendered.
    expect(find.text('Reseebo'), findsOneWidget);
    expect(find.text('Scan Receipt'), findsOneWidget);
    expect(find.text('Tindahan'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
