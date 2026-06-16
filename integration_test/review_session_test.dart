import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
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

// End-to-end coverage for the flashcard review feature: a full 10-card spaced-
// repetition session driven through the real UI. It exercises the recently
// reworked bits the audit flagged as untested:
//   - the per-card reveal + rate flow (Got it / Forgot),
//   - the back/forward card navigation (the back-gesture rework — stepping back
//     revisits an earlier card revealed with its prior rating, and the position
//     counter stays correct), and
//   - review persistence on exit (writeReviews → KEY_STORED_REVIEWS), which the
//     existing screenshot test walks but never asserts.

const int kSessionCards = 10;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'a 10-card review session reveals, rates, steps back and forward, and '
      'persists every review on exit', (WidgetTester tester) async {
    await setup();

    // Portrait phone viewport so the flashcard uses its vertical layout (reveal
    // / rating buttons and nav arrows on screen, not in a side panel).
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    advisoryShownOnce = true;

    // Seed a dedicated list with plenty of real, dictionary-backed videos so the
    // session has well over kSessionCards due cards to draw from. A separate
    // list (deleted in teardown) keeps the user's real favourites untouched.
    final saved = <SavedVideo>[];
    for (final e in entriesGlobal) {
      for (final sub in e.getSubEntries()) {
        for (final url in sub.getMedia()) {
          saved.add(SavedVideo(entryKey: e.getKey(), mediaPath: url));
        }
      }
      if (saved.length >= 30) break;
    }
    expect(saved.length, greaterThanOrEqualTo(kSessionCards),
        reason: 'need enough seed videos to fill the session');

    final listKey = EntryList.getKeyFromName('ReviewTest');
    if (!userEntryListManager.getEntryLists().containsKey(listKey)) {
      await userEntryListManager.createEntryList(listKey);
    }
    final testList = userEntryListManager.getEntryLists()[listKey]!;
    for (final v in saved) {
      await testList.addVideo(v);
    }
    addTearDown(() => userEntryListManager.deleteEntryList(listKey));

    // Configure the session: review the seeded list, spaced-repetition, capped
    // at exactly kSessionCards, both card directions on, and allow every region
    // so no seeded video is filtered out. Start review history from empty so the
    // post-session count is exact.
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

    // Revision tab -> Start the session.
    await tester.tap(find.byIcon(Icons.style));
    await settle(tester);
    final startButton = find.byKey(const ValueKey("startButton"));
    expect(startButton, findsOneWidget,
        reason: 'the revision landing page should offer a Start button');
    await tester.tap(startButton);
    await settle(tester);

    final revealButton = find.byKey(const ValueKey("revealButton"));
    final gotIt = find.byKey(const ValueKey("ratingButton.gotIt"));
    final forgot = find.byKey(const ValueKey("ratingButton.forgot"));

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

    // --- Cards 1-3: rate "Got it", landing on card 4. ---
    for (var k = 1; k <= 3; k++) {
      expect(find.text('$k / $kSessionCards'), findsOneWidget);
      await revealAndRate(forgotIt: false);
    }

    // On card 4, not yet revealed.
    expect(find.text('4 / $kSessionCards'), findsOneWidget);
    expect(revealButton, findsOneWidget);

    // --- Back/forward navigation. ---
    final back = find.byIcon(Icons.chevron_left);
    final forward = find.byIcon(Icons.chevron_right);

    // Step back to card 3: it reappears revealed with its earlier rating (so the
    // rating buttons, not the reveal button, are shown) and the counter tracks
    // the position rather than the answered-count.
    await tester.tap(back);
    await settle(tester);
    expect(find.text('3 / $kSessionCards'), findsOneWidget);
    expect(gotIt, findsOneWidget);
    expect(revealButton, findsNothing);

    // Keep stepping back to the first card; a further back tap is a no-op (we
    // never go below the first card).
    await tester.tap(back);
    await settle(tester);
    expect(find.text('2 / $kSessionCards'), findsOneWidget);
    await tester.tap(back);
    await settle(tester);
    expect(find.text('1 / $kSessionCards'), findsOneWidget);
    await tester.tap(back);
    await settle(tester);
    expect(find.text('1 / $kSessionCards'), findsOneWidget);

    // Walk forward through the already-shown cards back to card 4. Forward
    // navigation reuses the shown cards (no new draws), so we land exactly where
    // we left off — on the still-unrevealed card 4.
    for (var k = 2; k <= 4; k++) {
      await tester.tap(forward);
      await settle(tester);
      expect(find.text('$k / $kSessionCards'), findsOneWidget);
    }
    expect(revealButton, findsOneWidget);

    // --- Card 4: "Got it". Card 5: "Forgot". ---
    await revealAndRate(forgotIt: false);
    expect(find.text('5 / $kSessionCards'), findsOneWidget);
    await revealAndRate(forgotIt: true);

    // --- Cards 6-10: "Got it". The 10th advance ends the session. ---
    for (var k = 6; k <= kSessionCards; k++) {
      expect(find.text('$k / $kSessionCards'), findsOneWidget);
      await revealAndRate(forgotIt: false);
    }

    // Session complete: the summary replaces the card, so neither the reveal nor
    // the rating buttons remain.
    expect(revealButton, findsNothing);
    expect(gotIt, findsNothing);

    // Reviews are written when the session ends; the close button writes again
    // (idempotently) and pops back to the landing page.
    await tester.tap(find.byIcon(Icons.close));
    await settle(tester);

    // --- Persistence: exactly one review per card, with the single Forgot
    // recorded as Hard and the rest as Good. ---
    final reviews = readReviews();
    expect(reviews.length, kSessionCards,
        reason: 'one persisted review per reviewed card');
    expect(reviews.where((r) => r.rating == Rating.Hard).length, 1,
        reason: 'the one Forgot rating should persist as Hard');
    expect(
        reviews.where((r) => r.rating == Rating.Good).length, kSessionCards - 1,
        reason: 'the remaining ratings should persist as Good');
  });
}
