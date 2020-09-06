import 'package:flutter_test/flutter_test.dart';

import 'package:auslan_dictionary/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(MyApp());
  });
}
