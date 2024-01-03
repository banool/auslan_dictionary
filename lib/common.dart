import 'package:dictionarylib/entry_types.dart';
import 'package:flutter/material.dart';

import 'word_page.dart';

const String APP_NAME = "Auslan Dictionary";

const Color MAIN_COLOR = Colors.blue;
const Color APP_BAR_DISABLED_COLOR = Color.fromARGB(94, 0, 0, 0);

Future<void> navigateToEntryPage(
    BuildContext context, Entry entry, bool showFavouritesButton) {
  return Navigator.push(
    context,
    MaterialPageRoute(
        builder: (context) => EntryPage(
            entry: entry, showFavouritesButton: showFavouritesButton)),
  );
}
