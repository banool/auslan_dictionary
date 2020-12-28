import 'package:flutter/material.dart';

import 'types.dart';
import 'word_page.dart';

const String APP_NAME = "Auslan Dictionary";

const Color MAIN_COLOR = Colors.blue;

const String KEY_SHOULD_CACHE = "shouldCache";

void navigateToWordPage(BuildContext context, Word word, List<Word> allWords) {
  Navigator.push(
    context,
    MaterialPageRoute(
        builder: (context) => WordPage(word: word, allWords: allWords)),
  );
}
