import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:auslan_dictionary/main.dart';
import 'package:auslan_dictionary/root.dart';

import 'helpers.dart';

// Guards the alignment of the Hearth single-choice picker (used by the
// App theme / Colour mode settings rows). The bug this protects against:
// the option rows sat at a 15dp inset while the dialog title used the
// Material 24dp inset, so the options looked outdented to the left of the
// title. The fix lines the option labels up under the title; this test
// asserts their left edges match.

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app theme picker options line up under the dialog title',
      (WidgetTester tester) async {
    await setup();

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    advisoryShownOnce = true;

    await tester.pumpWidget(RootApp(startingLocale: LOCALE_ENGLISH));
    await settle(tester);

    // Settings tab -> open the App theme picker.
    await tester.tap(find.byIcon(Icons.settings));
    await settle(tester);
    final appThemeRow = find.text('App theme');
    await tester.ensureVisible(appThemeRow);
    await tester.tap(appThemeRow);
    await settle(tester);

    expect(find.byType(AlertDialog), findsOneWidget,
        reason: 'tapping the App theme row should open the picker dialog');

    // Scope every lookup to the dialog: the settings row behind the scrim
    // also shows "App theme" (its title) and "Hearth" (its current-value
    // trailing), so an unscoped find.text would match two widgets.
    final dialog = find.byType(AlertDialog);
    final dialogTitle =
        find.descendant(of: dialog, matching: find.text('App theme'));
    final hearthOption =
        find.descendant(of: dialog, matching: find.text('Hearth'));
    final classicOption =
        find.descendant(of: dialog, matching: find.text('Classic'));
    expect(dialogTitle, findsOneWidget);
    expect(hearthOption, findsOneWidget);
    expect(classicOption, findsOneWidget);

    final titleLeft = tester.getTopLeft(dialogTitle).dx;
    final hearthLeft = tester.getTopLeft(hearthOption).dx;
    final classicLeft = tester.getTopLeft(classicOption).dx;

    // Options align with each other and, crucially, with the title — not
    // outdented to its left as the pre-fix 15dp inset left them.
    expect((hearthLeft - classicLeft).abs(), lessThan(1.0),
        reason: 'the two options should share a left edge');
    expect((hearthLeft - titleLeft).abs(), lessThan(2.0),
        reason: 'options should line up under the title, not sit outdented');
  });
}
