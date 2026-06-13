import 'package:dictionarylib/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Guards that a toast dismisses when tapped *anywhere on the toast*, not just on
// the text. Every toast in the app — including the "Check for new dictionary
// data" toast — goes through dictionarylib's showSnack, so this exercises that
// shared helper directly.
//
// The bug this guards against: the tap-to-dismiss GestureDetector wrapped only
// the text, while the SnackBar added ~14px of padding above and below it. A tap
// on the coloured toast outside that thin text strip fell through and the toast
// stayed put. The cases below tap exactly those previously-dead padding regions.

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A bare screen whose button shows a coloured message toast, mirroring the
  // data-check toast (which passes a backgroundColor).
  Widget harness() => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showSnack(context, 'toast message',
                    backgroundColor: Colors.blue),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      );

  Future<void> showToast(WidgetTester tester) async {
    await tester.tap(find.text('show'));
    await tester.pump(); // schedule the toast
    await tester.pump(const Duration(milliseconds: 800)); // entrance animation
    expect(find.text('toast message'), findsOneWidget);
  }

  testWidgets('tapping the toast padding above the text dismisses it',
      (tester) async {
    await tester.pumpWidget(harness());
    await showToast(tester);

    final snack = tester.getRect(find.byType(SnackBar));
    final text = tester.getRect(find.text('toast message'));
    // 5px above the text: inside the coloured toast but outside the text — the
    // strip the old code left un-tappable.
    final tapY = text.top - 5;
    expect(tapY, greaterThan(snack.top),
        reason: 'tap point must be inside the toast');
    expect(tapY, lessThan(text.top),
        reason: 'tap point must be above the text');

    await tester.tapAt(Offset(text.center.dx, tapY));
    await tester.pumpAndSettle();
    expect(find.text('toast message'), findsNothing,
        reason: 'a tap in the toast padding should dismiss it');
  });

  testWidgets('tapping the toast padding below the text dismisses it',
      (tester) async {
    await tester.pumpWidget(harness());
    await showToast(tester);

    final snack = tester.getRect(find.byType(SnackBar));
    final text = tester.getRect(find.text('toast message'));
    // 5px below the text: inside the coloured toast but outside the text.
    final tapY = text.bottom + 5;
    expect(tapY, lessThan(snack.bottom),
        reason: 'tap point must be inside the toast');
    expect(tapY, greaterThan(text.bottom),
        reason: 'tap point must be below the text');

    await tester.tapAt(Offset(text.center.dx, tapY));
    await tester.pumpAndSettle();
    expect(find.text('toast message'), findsNothing,
        reason: 'a tap in the toast padding should dismiss it');
  });

  testWidgets('tapping the toast text dismisses it', (tester) async {
    await tester.pumpWidget(harness());
    await showToast(tester);

    await tester.tap(find.text('toast message'));
    await tester.pumpAndSettle();
    expect(find.text('toast message'), findsNothing);
  });
}
