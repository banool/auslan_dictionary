import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/flashcards_logic.dart' show KEY_USE_UNKNOWN_REGION_SIGNS;
import 'package:dictionarylib/globals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:auslan_dictionary/main.dart';
import 'package:auslan_dictionary/root.dart';

// End-to-end coverage for the sign-region configurator on the revision
// landing page:
//   - the "Signs with unknown region" toggle is presented as Recommended,
//     with the explanation of why (most signs aren't region-tagged), and
//   - the "Sign regions" row keeps a short one-line summary instead of
//     spelling out every selected region — it lists a handful but switches
//     to a count once more than three are on, so the row can't grow tall
//     and crowd the card.

Future<void> settle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  } catch (_) {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'region sheet recommends unknown-region signs and keeps a concise '
      'summary', (WidgetTester tester) async {
    await setup();

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    advisoryShownOnce = true;

    // Start from no extra regions selected, unknown-region signs on (the
    // default). Restore afterwards so we don't disturb real settings.
    final priorRegions =
        sharedPreferences.getStringList(KEY_FLASHCARD_REGIONS);
    final priorUnknown =
        sharedPreferences.getBool(KEY_USE_UNKNOWN_REGION_SIGNS);
    await sharedPreferences.setStringList(KEY_FLASHCARD_REGIONS, const []);
    await sharedPreferences.setBool(KEY_USE_UNKNOWN_REGION_SIGNS, true);
    addTearDown(() async {
      if (priorRegions == null) {
        await sharedPreferences.remove(KEY_FLASHCARD_REGIONS);
      } else {
        await sharedPreferences.setStringList(KEY_FLASHCARD_REGIONS, priorRegions);
      }
      if (priorUnknown == null) {
        await sharedPreferences.remove(KEY_USE_UNKNOWN_REGION_SIGNS);
      } else {
        await sharedPreferences.setBool(KEY_USE_UNKNOWN_REGION_SIGNS, priorUnknown);
      }
    });

    await tester.pumpWidget(RootApp(startingLocale: LOCALE_ENGLISH));
    await settle(tester);

    // Revision tab -> the flashcards landing, where the Sign regions row lives.
    await tester.tap(find.byIcon(Icons.style));
    await settle(tester);

    // The landing is a lazy ListView and the Sign regions row sits at the
    // bottom, so scroll it into view (and build it) before interacting.
    final regionsRow = find.text('Sign regions');
    await tester.scrollUntilVisible(regionsRow, 250,
        scrollable: find.byType(Scrollable).first);
    await settle(tester);

    // --- Open the sheet: the unknown-region toggle is flagged Recommended. ---
    await tester.tap(regionsRow);
    await settle(tester);
    expect(find.text('Recommended'), findsOneWidget,
        reason: 'the unknown-region toggle should be marked Recommended');
    expect(find.textContaining("Most signs aren't tagged with a region"),
        findsOneWidget,
        reason: 'the sheet should explain why keeping it on is recommended');

    // --- Select four regions, then close: the summary collapses to a count. ---
    for (final r in const ['NSW', 'VIC', 'QLD', 'SA']) {
      final pill = find.text(r);
      await tester.ensureVisible(pill);
      await tester.tap(pill);
      await settle(tester);
    }
    await _tapDone(tester);
    expect(find.textContaining('4 regions'), findsOneWidget,
        reason: 'more than three regions should summarise as a count, not a '
            'long wrapping list');

    // --- Drop back to three: now it lists them by name. ---
    await tester.tap(find.text('Sign regions'));
    await settle(tester);
    final saPill = find.text('SA');
    await tester.ensureVisible(saPill);
    await tester.tap(saPill); // deselect the fourth
    await settle(tester);
    await _tapDone(tester);
    expect(find.textContaining('NSW, VIC, QLD'), findsOneWidget,
        reason: 'three or fewer regions should be listed by name');
    // The count form ("3 regions") must not show when they're listed. (Note
    // the row's own "Sign regions" title legitimately contains "regions".)
    expect(find.textContaining('3 regions'), findsNothing,
        reason: 'the count form should not show when regions are listed');
  });
}

Future<void> _tapDone(WidgetTester tester) async {
  final done = find.text('Done');
  await tester.ensureVisible(done);
  await settle(tester);
  await tester.tap(done);
  await settle(tester);
}
