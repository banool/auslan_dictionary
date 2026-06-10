import 'package:flutter_test/flutter_test.dart';

/// pumpAndSettle, but tolerant of the video player: a buffering media_kit
/// player can keep scheduling frames so pumpAndSettle never converges (and the
/// fully-live frame policy these integration tests run under makes that more
/// likely). Fall back to a few fixed pumps in that case.
///
/// Shared by the integration_test suites so the same settle behaviour lives in
/// one place.
Future<void> settle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  } catch (_) {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }
}
