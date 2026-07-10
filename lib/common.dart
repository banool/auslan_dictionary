import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/root_app.dart' show defaultNavigateToEntryPage;
import 'package:dictionarylib/saved_video.dart';
import 'package:flutter/material.dart';

import 'word_page.dart';

const String APP_NAME = "Auslan Dictionary";

const MaterialColor MAIN_COLOR = Colors.blue;

const String IOS_APP_ID = "1531368368";
const String ANDROID_APP_ID = "com.banool.auslan_dictionary";

/// Open an entry — dictionarylib's shared web-route / native-push navigation
/// with this app's word-page config. A plain function (not a curried final):
/// auslanWordPageConfig itself references this, so eagerly evaluating the
/// config here would recurse during lazy initialization.
Future<void> navigateToEntryPage(
    BuildContext context, Entry entry, bool showFavouritesButton,
    {SavedVideo? focusVideo, EntryList? saveToList}) {
  return defaultNavigateToEntryPage(context, entry, showFavouritesButton,
      focusVideo: focusVideo,
      saveToList: saveToList,
      config: auslanWordPageConfig);
}
