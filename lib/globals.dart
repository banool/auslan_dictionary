import 'package:shared_preferences/shared_preferences.dart';

import 'types.dart';

late List<Word> wordsGlobal;
late SharedPreferences sharedPreferences;

// This is the value of the knob.
late bool enableFlashcardsKnob;

// This is whether to show the flashcard stuff as a result of the knob + switch.
late bool showFlashcards;
