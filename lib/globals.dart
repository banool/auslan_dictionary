import 'dart:ui';

import 'package:auslan_dictionary/word_list_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'types.dart';

late Set<Word> wordsGlobal;
late Map<String, Word> keyedWordsGlobal = {};
late Set<Word> favouritesGlobal;

late WordListManager wordListManager;

late SharedPreferences sharedPreferences;

// Values of the knobs.
late bool enableFlashcardsKnob;
late bool downloadWordsDataKnob;
late bool useWordListsKnob;

// This is whether to show the flashcard stuff as a result of the knob + switch.
late bool showFlashcards;

// The settings page background color.
late Color settingsBackgroundColor;
