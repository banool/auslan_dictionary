import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/page_entry_list_overview.dart'
    show KEY_LISTS_OVERVIEW_TAB_INDEX;
import 'package:dictionarylib/saved_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:auslan_dictionary/main.dart';
import 'package:auslan_dictionary/root.dart';

import 'helpers.dart';

// End-to-end coverage for tap-to-rename in the lists overview's edit mode,
// and the guarantee that favourites — whose key is fixed — can never be
// renamed through the UI.
//
// The list is seeded directly (not created via the dialog) so the test
// targets a known name, then driven through the real edit-mode tap → rename
// dialog → confirm flow. It asserts both the visible result and that the
// list's saved videos survive the underlying key change.

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'edit mode: tapping a list renames it (videos preserved); favourites '
      'cannot be renamed', (WidgetTester tester) async {
    await setup();

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    advisoryShownOnce = true;
    // Pin the overview to the My Lists tab so the edit pencil + our seeded
    // list are on the visible tab regardless of what a previous run left.
    await sharedPreferences.setInt(KEY_LISTS_OVERVIEW_TAB_INDEX, 0);

    // Seed a renamable list with one real saved video so we can prove the
    // rename carries the contents across the key change.
    const startKey = 'RenameMe_words';
    const endKey = 'Renamed_words';
    final entry = entriesGlobal.firstWhere(
        (e) => e.getSubEntries().any((s) => s.getMedia().isNotEmpty));
    final video = SavedVideo(
        entryKey: entry.getKey(),
        mediaPath: entry
            .getSubEntries()
            .firstWhere((s) => s.getMedia().isNotEmpty)
            .getMedia()
            .first);

    Future<void> cleanup() async {
      for (final k in [startKey, endKey]) {
        if (userEntryListManager.getEntryLists().containsKey(k)) {
          await userEntryListManager.deleteEntryList(k);
        }
      }
    }

    await cleanup();
    await userEntryListManager.createEntryList(startKey);
    await userEntryListManager.getEntryLists()[startKey]!.addVideo(video);
    addTearDown(cleanup);

    await tester.pumpWidget(RootApp(startingLocale: LOCALE_ENGLISH));
    await settle(tester);

    // Lists tab -> My Lists.
    await tester.tap(find.byIcon(Icons.view_list));
    await settle(tester);
    expect(find.text('RenameMe'), findsOneWidget,
        reason: 'the seeded list should be on the My Lists tab');

    // Enter edit mode (the pencil flips from outline to filled).
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await settle(tester);

    // --- Rename the seeded list by tapping it. ---
    await tester.tap(find.text('RenameMe'));
    await settle(tester);
    expect(find.text('Rename List'), findsOneWidget,
        reason: 'tapping a list in edit mode should open the rename dialog');
    // The dialog is pre-filled with the current name.
    expect(find.widgetWithText(TextField, 'RenameMe'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Renamed');
    await tester.tap(find.text('Confirm'));
    await settle(tester);

    // The list now lives under the new key, kept its saved video, and the
    // old key is gone.
    final lists = userEntryListManager.getEntryLists();
    expect(lists.containsKey(endKey), isTrue,
        reason: 'rename should move the list to the new key');
    expect(lists.containsKey(startKey), isFalse,
        reason: 'the old key should be gone after rename');
    expect(lists[endKey]!.containsVideo(video), isTrue,
        reason: 'the saved video should survive the rename');
    expect(find.text('Renamed'), findsOneWidget,
        reason: 'the renamed list should show its new name');
    expect(find.text('RenameMe'), findsNothing);

    // --- Favourites cannot be renamed. ---
    // Still in edit mode. Favourites is wrapped in an IgnorePointer, so the
    // tap is swallowed and no rename dialog appears.
    expect(find.text('Favourites'), findsOneWidget);
    await tester.tap(find.text('Favourites'), warnIfMissed: false);
    await settle(tester);
    expect(find.text('Rename List'), findsNothing,
        reason: 'favourites must not be renamable');
    // Favourites is still under its fixed key.
    expect(userEntryListManager.getEntryLists().keys.first,
        KEY_FAVOURITES_ENTRIES);
  });
}
