import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib_test_support/config.dart';

import 'package:auslan_dictionary/common.dart' as app;
import 'package:auslan_dictionary/entries_types.dart' as et;
import 'package:auslan_dictionary/main.dart';
import 'package:auslan_dictionary/root.dart';

/// Auslan's plug-in points for the shared integration-test suites in
/// dictionarylib_test_support.
final DictAppTestConfig appTestConfig = DictAppTestConfig(
  setup: () => setup(),
  buildApp: (locale) => RootApp(startingLocale: locale),
  navigateToEntryPage: app.navigateToEntryPage,
  // Auslan filters the flashcard pool by region; allow every region (and
  // unknown-region signs) so no seeded video is filtered out.
  seedFlashcardSettings: () async {
    await sharedPreferences.setStringList(KEY_FLASHCARD_REGIONS,
        [for (var i = 0; i < et.Region.values.length; i++) '$i']);
    await sharedPreferences.setBool(KEY_USE_UNKNOWN_REGION_SIGNS, true);
  },
  clearFlashcardSettings: () async {
    await sharedPreferences.remove(KEY_FLASHCARD_REGIONS);
  },
);

const ScreenshotSuiteConfig screenshotConfig = ScreenshotSuiteConfig(
  localeDirName: 'en-AU',
  animalsSeedWords: ["kangaroo", "platypus", "echidna", "dog", "cat", "bird"],
  searchQuery: 'dog',
  heroEntryKey: 'dog',
);
