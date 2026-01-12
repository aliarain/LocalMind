// Basic Flutter widget test for LocalMind.

import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/app.dart';

void main() {
  testWidgets('LocalMind app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const LocalMindApp());

    // Verify app name is displayed
    expect(find.text('Local Mind'), findsOneWidget);
  });
}
