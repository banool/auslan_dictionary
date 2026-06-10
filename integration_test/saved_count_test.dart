import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:auslan_dictionary/common.dart' as app;
import 'package:auslan_dictionary/main.dart';
import 'package:auslan_dictionary/root.dart';

// End-to-end coverage for the word page's "saved to N lists" count. It is
// computed from the same writable-list set the save sheet shows
// (ListsService.writableLists), so the label and the sheet's ticked rows
// can't disagree: saving a video into two lists reads back as "Saved to 2
// lists", and clearing both drops the button back to "Save".

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
      'the word-page count tracks every writable list the video is saved in',
      (WidgetTester tester) async {
    await setup();

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    advisoryShownOnce = true;

    // A deterministic entry: one sub-entry (single bookmark button, no
    // PageView siblings) with at least one video. The button saves the first
    // shown video.
    final entry = entriesGlobal.firstWhere((e) {
      final subs = e.getSubEntries();
      return subs.length == 1 && subs.first.getMedia().isNotEmpty;
    });
    final video = SavedVideo(
        entryKey: entry.getKey(),
        videoUrl: entry.getSubEntries().first.getMedia().first);

    final favList =
        userEntryListManager.getEntryLists()[KEY_FAVOURITES_ENTRIES]!;
    const secondKey = 'CountTest_words';

    Future<void> cleanup() async {
      if (favList.containsVideo(video)) await favList.removeVideo(video);
      if (userEntryListManager.getEntryLists().containsKey(secondKey)) {
        await userEntryListManager.deleteEntryList(secondKey);
      }
    }

    await cleanup();
    await userEntryListManager.createEntryList(secondKey);
    addTearDown(cleanup);

    await tester.pumpWidget(RootApp(startingLocale: LOCALE_ENGLISH));
    await settle(tester);

    // Open the entry's word page in picker-sheet mode (no saveToList).
    app.navigateToEntryPage(rootNavigatorKey.currentContext!, entry, true);
    await settle(tester);

    final saveButton = find.byKey(const ValueKey('wordPage.saveButton'));
    expect(saveButton, findsOneWidget);
    expect(find.text('Save'), findsOneWidget,
        reason: 'the video starts saved to no lists');

    final favRow =
        find.byKey(ValueKey('saveVideoSheet.row.$KEY_FAVOURITES_ENTRIES'));
    final secondRow = find.byKey(ValueKey('saveVideoSheet.row.$secondKey'));

    // --- Save into both lists, close the sheet, expect "Saved to 2 lists". ---
    await tester.tap(saveButton);
    await settle(tester);
    expect(secondRow, findsOneWidget,
        reason: 'the sheet should offer the second user list as a target');
    await tester.tap(favRow);
    await settle(tester);
    await tester.tap(secondRow);
    await settle(tester);
    rootNavigatorKey.currentState!.pop(); // close the sheet
    await settle(tester);

    expect(favList.containsVideo(video), isTrue);
    expect(find.text('Saved to 2 lists'), findsOneWidget,
        reason: 'the count should include both writable lists');

    // --- Clear both, close, expect the button back to "Save". ---
    await tester.tap(saveButton);
    await settle(tester);
    await tester.tap(favRow);
    await settle(tester);
    await tester.tap(secondRow);
    await settle(tester);
    rootNavigatorKey.currentState!.pop();
    await settle(tester);

    expect(find.text('Saved to 2 lists'), findsNothing);
    expect(find.text('Save'), findsOneWidget,
        reason: 'unsaving from every list returns the button to Save');
  });
}
