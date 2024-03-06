import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/force_upgrade_page.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'word_page.dart';

const String APP_NAME = "Auslan Dictionary";

const Color MAIN_COLOR = Colors.blue;
const Color APP_BAR_DISABLED_COLOR = Color.fromARGB(94, 0, 0, 0);

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

// We set a short timeout because if we fail to get the yanked versions and it
// turns out they're running a yanked version, the worst case is just that
// they'll go to the error fallback page instead, which is just more confusing.
// Given most people will not be on yanked versions we don't want to make this
// add too much startup latency.
class MyYankedVersionChecker extends YankedVersionChecker {
  @override
  Future<List<String>> getYankedVersions() async {
    try {
      var response = await http
          .get(Uri.parse(
              'https://raw.githubusercontent.com/banool/auslan_dictionary/master/assets/yanked_versions'))
          .timeout(const Duration(milliseconds: 2250));
      if (response.statusCode != 200) {
        throw "HTTP response for getting yanked versions was non 200: ${response.statusCode}";
      }
      return response.body.split("\n");
    } catch (e) {
      printAndLog(
          "Failed to get yanked versions, continuing without raising an error: $e");
      return [];
    }
  }
}
