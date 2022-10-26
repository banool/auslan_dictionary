import 'dart:ui';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'types.dart';
import 'word_list_logic.dart';

late Set<Word> wordsGlobal;
late Map<String, Word> keyedWordsGlobal = {};
late Set<Word> favouritesGlobal;

late WordListManager wordListManager;

late SharedPreferences sharedPreferences;
late CacheManager videoCacheManager;

// Values of the knobs.
late bool enableFlashcardsKnob;
late bool downloadWordsDataKnob;

// This is whether to show the flashcard stuff as a result of the knob + switch.
late bool showFlashcards;

// The settings page background color.
late Color settingsBackgroundColor;

// Advisory if there is a new one.
String? advisory;
bool advisoryShownOnce = false;
