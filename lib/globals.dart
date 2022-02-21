import 'package:shared_preferences/shared_preferences.dart';

import 'types.dart';

late List<Word> wordsGlobal;
late SharedPreferences sharedPreferences;

// Values of the knobs.
late bool enableFlashcardsKnob;
late bool downloadWordsDataKnob;

// This is whether to show the flashcard stuff as a result of the knob + switch.
late bool showFlashcards;
