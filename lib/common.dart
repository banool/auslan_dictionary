import 'package:dictionarylib/entry_types.dart';
import 'package:flutter/material.dart';

import 'word_page.dart';

const String APP_NAME = "Auslan Dictionary";

// const Color MAIN_COLOR = Colors.blue;
// const Color APP_BAR_DISABLED_COLOR = Color.fromARGB(94, 0, 0, 0);

const String IOS_APP_ID = "1531368368";
const String ANDROID_APP_ID = "com.banool.auslan_dictionary";

Future<void> navigateToEntryPage(
    BuildContext context, Entry entry, bool showFavouritesButton) {
  return Navigator.push(
    context,
    MaterialPageRoute(
        builder: (context) => EntryPage(
            entry: entry, showFavouritesButton: showFavouritesButton)),
  );
}
