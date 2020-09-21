import 'package:flutter/material.dart';

import 'types.dart';
import 'word_page.dart';

const String KEY_SHOULD_CACHE = "shouldCache";

void navigateToWordPage(BuildContext context, Word word, List<Word> allWords) {
  Navigator.push(
    context,
    MaterialPageRoute(
        builder: (context) => WordPage(word: word, allWords: allWords)),
  );
}
