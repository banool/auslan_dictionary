import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/page_entry_list_overview.dart'
    show KEY_LISTS_OVERVIEW_TAB_INDEX;
import 'package:dictionarylib/saved_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:auslan_dictionary/common.dart' as app;
import 'package:auslan_dictionary/main.dart';
import 'package:auslan_dictionary/root.dart';

// End-to-end coverage for the "save individual videos rather than entire
// entries" feature. It drives the real per-video bookmark button, the real
// save-to-list sheet, and asserts the toggle both persists to disk (a fresh
// read sees it) and surfaces in the list view.
//
// The word page is reached programmatically (the same push the search results
// use, with no saveToList, so the bookmark button opens the all-lists picker
// sheet) rather than by typing in search, so the test targets a known entry
// and isn't at the mercy of search-result ordering / lazy list building.

/// pumpAndSettle, but tolerant of the video player: a buffering media_kit
/// player can keep scheduling frames so pumpAndSettle never converges. Fall
/// back to a few fixed pumps in that case.
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
      'saving an individual video toggles, persists across reload, and '
      'surfaces in the list view', (WidgetTester tester) async {
    await setup();

    // Pin a phone-sized portrait viewport so the entry page uses its vertical
    // layout (bookmark button directly under the video, on screen) rather than
    // the wide/landscape layout where it lives in a scrollable side panel.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Don't let the once-per-session advisories interstitial push the News
    // page over the search screen and derail navigation.
    advisoryShownOnce = true;

    // The lists overview restores its last-active tab from storage; pin it to
    // My Lists (index 0) so the Favourites tile is on the visible tab
    // regardless of what tab a previous run/device session left selected.
    await sharedPreferences.setInt(KEY_LISTS_OVERVIEW_TAB_INDEX, 0);

    // Pick a deterministic entry: exactly one sub-entry (so there's a single
    // bookmark button, no PageView siblings) with at least one video.
    final entry = entriesGlobal.firstWhere((e) {
      final subs = e.getSubEntries();
      return subs.length == 1 && subs.first.getMedia().isNotEmpty;
    });
    // The button saves the currently-shown video, which is the first
    // sub-entry's first video when the page opens with no focusVideo.
    final expected = SavedVideo(
        entryKey: entry.getKey(), videoUrl: entry.getSubEntries().first.getMedia().first);

    final favList =
        userEntryListManager.getEntryLists()[KEY_FAVOURITES_ENTRIES]!;
    // Start from a clean slate and leave it clean afterwards, so the test is
    // re-runnable and doesn't pollute the simulator's real favourites.
    Future<void> ensureNotSaved() async {
      if (favList.containsVideo(expected)) await favList.removeVideo(expected);
    }

    await ensureNotSaved();
    addTearDown(ensureNotSaved);
    expect(favList.containsVideo(expected), isFalse,
        reason: 'precondition: video should not be saved yet');

    await tester.pumpWidget(RootApp(startingLocale: LOCALE_ENGLISH));
    await settle(tester);

    // Open the entry's word page in picker-sheet mode (showFavouritesButton:
    // true, no saveToList).
    app.navigateToEntryPage(rootNavigatorKey.currentContext!, entry, true);
    await settle(tester);

    final saveButton = find.byKey(const ValueKey('wordPage.saveButton'));
    expect(saveButton, findsOneWidget,
        reason: 'the per-video bookmark button should be on the word page');

    // Tap it to open the all-lists save sheet.
    await tester.tap(saveButton);
    await settle(tester);

    final favouritesRow =
        find.byKey(ValueKey('saveVideoSheet.row.$KEY_FAVOURITES_ENTRIES'));
    expect(favouritesRow, findsOneWidget,
        reason: 'the save sheet should list the Favourites list');

    // --- Toggle ON ---
    await tester.tap(favouritesRow);
    await settle(tester);
    expect(favList.containsVideo(expected), isTrue,
        reason: 'tapping the row should add the video to Favourites');
    // The durable write is what a fresh launch reads back — assert against a
    // straight-from-SharedPreferences reload, not just the in-memory list.
    expect(EntryList.loadSavedVideos(KEY_FAVOURITES_ENTRIES).contains(expected),
        isTrue,
        reason: 'the saved video should persist to storage');
    // The reloaded list should report the entry, i.e. it would render as a row
    // in the list view.
    expect(EntryList.fromRaw(KEY_FAVOURITES_ENTRIES).containsEntry(entry),
        isTrue,
        reason: 'the entry should appear in the reloaded list');

    // --- Toggle OFF (removal also persists) ---
    await tester.tap(favouritesRow);
    await settle(tester);
    expect(favList.containsVideo(expected), isFalse,
        reason: 'tapping again should remove the video');
    expect(EntryList.loadSavedVideos(KEY_FAVOURITES_ENTRIES).contains(expected),
        isFalse,
        reason: 'the removal should persist to storage');

    // --- Toggle ON again, then verify it shows in the real list UI ---
    await tester.tap(favouritesRow);
    await settle(tester);
    expect(favList.containsVideo(expected), isTrue);

    // Close the sheet, then the word page, so the bottom nav on the search
    // screen is reachable. Both routes sit on the root navigator (the sheet
    // and the entry page were pushed there), so pop it twice.
    rootNavigatorKey.currentState!.pop();
    await settle(tester);
    rootNavigatorKey.currentState!.pop();
    await settle(tester);

    // Lists tab -> open Favourites -> the entry row should be present.
    await tester.tap(find.byIcon(Icons.view_list));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey(KEY_FAVOURITES_ENTRIES)));
    await settle(tester);
    expect(find.byKey(ValueKey(entry.getKey())), findsOneWidget,
        reason: 'the saved video\'s entry should be a row in the list view');
  });
}
