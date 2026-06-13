import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/hearth.dart';
import 'package:dictionarylib/revision.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dolphinsr_dart/dolphinsr_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:auslan_dictionary/entries_types.dart' as et;
import 'package:auslan_dictionary/main.dart';
import 'package:auslan_dictionary/root.dart';

import 'helpers.dart';

// Exiting a revision session early (via the × button) should show the same
// summary screen you get by finishing a session start-to-finish — the answers
// so far are persisted either way, so there's no reason to hide the results.
// Exiting before answering anything has nothing to summarise, so that case still
// goes straight back to the revision landing page.

const int kSessionCards = 10;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'exiting a session part way shows the summary and persists the answers '
      'so far; exiting before answering anything returns to the landing page',
      (WidgetTester tester) async {
    await setup();

    // Portrait phone viewport so the flashcard uses its vertical layout (reveal
    // / rating buttons and nav arrows on screen, not in a side panel).
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    advisoryShownOnce = true;

    // Seed a dedicated list with plenty of real, dictionary-backed videos so the
    // session has well over kSessionCards due cards to draw from. A separate list
    // (deleted in teardown) keeps the user's real favourites untouched.
    final saved = <SavedVideo>[];
    for (final e in entriesGlobal) {
      for (final sub in e.getSubEntries()) {
        for (final url in sub.getMedia()) {
          saved.add(SavedVideo(entryKey: e.getKey(), videoUrl: url));
        }
      }
      if (saved.length >= 30) break;
    }
    expect(saved.length, greaterThanOrEqualTo(kSessionCards),
        reason: 'need enough seed videos to fill the session');

    final listKey = EntryList.getKeyFromName('EarlyExitTest');
    if (!userEntryListManager.getEntryLists().containsKey(listKey)) {
      await userEntryListManager.createEntryList(listKey);
    }
    final testList = userEntryListManager.getEntryLists()[listKey]!;
    for (final v in saved) {
      await testList.addVideo(v);
    }
    addTearDown(() => userEntryListManager.deleteEntryList(listKey));

    // Configure the session: review the seeded list, spaced-repetition, capped at
    // kSessionCards, both card directions on, and allow every region so no seeded
    // video is filtered out. Start review history from empty so the persisted
    // counts are exact.
    await sharedPreferences.setStringList(KEY_LISTS_TO_REVIEW, [listKey]);
    await sharedPreferences.setInt(
        KEY_REVISION_STRATEGY, RevisionStrategy.SpacedRepetition.index);
    await sharedPreferences.setInt(KEY_REVISION_CARD_LIMIT, kSessionCards);
    await sharedPreferences.setBool(KEY_WORD_TO_SIGN, true);
    await sharedPreferences.setBool(KEY_SIGN_TO_WORD, true);
    await sharedPreferences.setStringList(KEY_FLASHCARD_REGIONS,
        [for (var i = 0; i < et.Region.values.length; i++) '$i']);
    await sharedPreferences.setBool(KEY_USE_UNKNOWN_REGION_SIGNS, true);
    await sharedPreferences.remove(KEY_STORED_REVIEWS);
    addTearDown(() async {
      await sharedPreferences.remove(KEY_STORED_REVIEWS);
      await sharedPreferences.remove(KEY_REVISION_CARD_LIMIT);
      await sharedPreferences.remove(KEY_FLASHCARD_REGIONS);
      await sharedPreferences
          .setStringList(KEY_LISTS_TO_REVIEW, [KEY_FAVOURITES_ENTRIES]);
    });

    await tester.pumpWidget(RootApp(startingLocale: LOCALE_ENGLISH));
    await settle(tester);

    final startButton = find.byKey(const ValueKey("startButton"));
    final revealButton = find.byKey(const ValueKey("revealButton"));
    final gotIt = find.byKey(const ValueKey("ratingButton.gotIt"));
    final forgot = find.byKey(const ValueKey("ratingButton.forgot"));
    // The AppBar leading IconButton — disambiguated from the "Forgot" rating
    // button, which also uses Icons.close but is a FilledButton/OutlinedButton.
    final closeButton = find.widgetWithIcon(IconButton, Icons.close);
    // The summary screen's three stat tiles (Cards / Got it / Forgot) — a
    // localisation-independent marker that we're on the summary.
    final summaryStats = find.byType(HearthStatTile);

    // Tap Start on the revision landing page. We only ever tap the bottom-nav
    // revision tab once (below); once the landing page has been built its body
    // also renders an Icons.style glyph, so re-tapping the tab by icon would be
    // ambiguous. Every session after the first starts from the landing page we
    // popped back to, so it just needs Start.
    Future<void> tapStart() async {
      expect(startButton, findsOneWidget,
          reason: 'the revision landing page should offer a Start button');
      await tester.tap(startButton);
      await settle(tester);
    }

    // Reveal the current card and rate it, advancing to the next card. Revealing
    // records a default "Got it"; tapping Forgot overwrites it to Hard and waits
    // out the brief feedback timer before the card auto-advances.
    Future<void> revealAndRate({required bool forgotIt}) async {
      expect(revealButton, findsOneWidget);
      await tester.tap(revealButton);
      await settle(tester);
      if (forgotIt) {
        await tester.tap(forgot);
        await tester
            .pump(const Duration(seconds: 1)); // feedback timer (~750ms)
        await settle(tester);
      } else {
        await tester.tap(gotIt);
        await settle(tester);
      }
    }

    // === Scenario 1: exit part way -> summary, partial answers persisted. ===
    await tester.tap(find.byIcon(Icons.style)); // search tab -> revision tab
    await settle(tester);
    await tapStart();

    // Answer three of the ten cards (two Got it, one Forgot), leaving us on the
    // still-unrevealed fourth card: mid-session, not finished.
    await revealAndRate(forgotIt: false);
    await revealAndRate(forgotIt: false);
    await revealAndRate(forgotIt: true);
    expect(find.text('4 / $kSessionCards'), findsOneWidget,
        reason: 'should be on the 4th card, session not yet finished');

    // Exit early via the × button.
    await tester.tap(closeButton);
    await settle(tester);

    // We're on the summary, not on a card and not back on the landing page: the
    // reveal/rating buttons are gone, the per-card counter is gone, the summary
    // stat tiles are present, and the landing page's Start button is absent.
    expect(revealButton, findsNothing);
    expect(gotIt, findsNothing);
    expect(find.text('4 / $kSessionCards'), findsNothing);
    expect(summaryStats, findsWidgets,
        reason: 'exiting part way should land on the revision summary');
    expect(startButton, findsNothing,
        reason: 'exiting part way should not drop back to the landing page');

    // The three answers so far are persisted (one Hard, two Good) — the whole
    // reason it's safe to show the summary on early exit.
    final partial = readReviews();
    expect(partial.length, 3,
        reason: 'one persisted review per answered card so far');
    expect(partial.where((r) => r.rating == Rating.Hard).length, 1,
        reason: 'the one Forgot rating should persist as Hard');
    expect(partial.where((r) => r.rating == Rating.Good).length, 2,
        reason: 'the two Got it ratings should persist as Good');

    // From the summary, × leaves revision and returns to the landing page.
    await tester.tap(closeButton);
    await settle(tester);
    expect(startButton, findsOneWidget,
        reason: 'closing the summary returns to the landing page');

    // === Scenario 2: exit before answering anything -> straight to landing. ===
    // (We're already on the revision landing page, so just tap Start again.)
    await sharedPreferences.remove(KEY_STORED_REVIEWS);
    await tapStart();
    expect(revealButton, findsOneWidget,
        reason: 'a fresh session should show its first, unrevealed card');

    await tester.tap(closeButton);
    await settle(tester);

    // Nothing was answered, so there's nothing to summarise: straight back to the
    // landing page with no summary shown.
    expect(startButton, findsOneWidget,
        reason: 'exiting with no answers returns to the landing page');
    expect(summaryStats, findsNothing,
        reason: 'no summary when nothing was answered');
  });
}
