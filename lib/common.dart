import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:edit_distance/edit_distance.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'globals.dart';
import 'types.dart';
import 'word_page.dart';

const String APP_NAME = "Auslan Dictionary";

const Color MAIN_COLOR = Colors.blue;
const Color APP_BAR_DISABLED_COLOR = Color.fromARGB(94, 0, 0, 0);

const String KEY_SHOULD_CACHE = "shouldCache";

const String KEY_FAVOURITES_WORDS = "favourites_words";
const String KEY_LAST_DICTIONARY_DATA_CHECK_TIME = "last_data_check_time";
const String KEY_DICTIONARY_DATA_CURRENT_VERSION = "current_data_version";
const String KEY_HIDE_FLASHCARDS_FEATURE = "hide_flashcards_feature";
const String KEY_FLASHCARD_REGIONS = "flashcard_regions";

const int DATA_CHECK_INTERVAL = 60 * 60 * 24 * 7; // 1 week.

Future<Set<Word>> loadWords() async {
  String data;
  try {
    // First try to read from the file we downloaded from the internet.
    final path = await _dictionaryDataFilePath;
    data = await path.readAsString();
    print("Loaded data from local storage downloaded from the internet");
    return loadWordsInner(data);
  } catch (e) {
    // That failed, it probably wasn't there or it was invalid, use data bundled in.
    print(
        "Failed to use data from internet, using local bundled data instead: $e");
    data = await rootBundle.loadString("assets/data/words_latest.json");
    return loadWordsInner(data);
  }
}

Set<Word> loadWordsInner(String data) {
  dynamic wordsJson = json.decode(data);
  Set<Word> words = {};
  for (MapEntry e in wordsJson.entries) {
    words.add(Word.fromJson(e.key, e.value));
  }
  print("Loaded ${words.length} words");
  return words;
}

Future<void> navigateToWordPage(BuildContext context, Word word,
    {bool showFavouritesButton = true}) {
  return Navigator.push(
    context,
    MaterialPageRoute(
        builder: (context) =>
            WordPage(word: word, showFavouritesButton: showFavouritesButton)),
  );
}

// Search a list of words and return top matching items.
List<Word> searchList(String searchTerm, Set<Word> words, Set<Word> fallback) {
  final SplayTreeMap<double, List<Word>> st =
      SplayTreeMap<double, List<Word>>();
  if (searchTerm == "") {
    return List.from(fallback);
  }
  searchTerm = searchTerm.toLowerCase();
  JaroWinkler d = new JaroWinkler();
  RegExp noParenthesesRegExp = new RegExp(
    r"^[^ (]*",
    caseSensitive: false,
    multiLine: false,
  );
  for (Word w in words) {
    String noPunctuation = w.word.replaceAll(" ", "").replaceAll(",", "");
    String lowerCase = noPunctuation.toLowerCase();
    String noParenthesesContent = noParenthesesRegExp.stringMatch(lowerCase)!;
    String normalisedWord = noParenthesesContent;
    double difference = d.normalizedDistance(normalisedWord, searchTerm);
    if (difference == 1.0) {
      continue;
    }
    st.putIfAbsent(difference, () => []).add(w);
  }
  List<Word> out = [];
  for (List<Word> words in st.values) {
    out.addAll(words);
    if (out.length > 10) {
      break;
    }
  }
  return out;
}

// Run this at startup.
// Downloads new dictionary data if available.
// First it checks how recently it attempted to do this, so we don't spam
// the dictionary data server.
// Returns true if new data was downloaded.
Future<bool> getNewData(bool forceCheck) async {
  // Determine whether it is time to check for new dictionary data.
  int? lastCheckTime =
      sharedPreferences.getInt(KEY_LAST_DICTIONARY_DATA_CHECK_TIME);
  int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  if (!(lastCheckTime == null ||
      now - DATA_CHECK_INTERVAL > lastCheckTime ||
      forceCheck)) {
    // No need to check again so soon.
    print("Not checking for new dictionary data, it hasn't been long enough");
    return false;
  }
  // Check for new dictionary data.
  int currentVersion =
      sharedPreferences.getInt(KEY_DICTIONARY_DATA_CURRENT_VERSION) ?? 0;
  int latestVersion = int.parse((await http.get(Uri.parse(
          'https://raw.githubusercontent.com/banool/auslan_dictionary/master/assets/data/latest_version')))
      .body);
  if (latestVersion <= currentVersion) {
    print(
        "Current version ($currentVersion) is >= latest version ($latestVersion), not downloading new data");
    // Record that we made this check so we don't check again too soon.
    await sharedPreferences.setInt(KEY_LAST_DICTIONARY_DATA_CHECK_TIME, now);
    return false;
  }
  // At this point, we know we need to download the new data. Let's do that.
  String newData = (await http.get(Uri.parse(
          'https://raw.githubusercontent.com/banool/auslan_dictionary/master/assets/data/words_latest.json')))
      .body;
  // Assert that the data is valid. This will throw if it's not.
  loadWordsInner(newData);
  // Write the data to file.
  final path = await _dictionaryDataFilePath;
  await path.writeAsString(newData);
  // Now, record the new version that we downloaded.
  await sharedPreferences.setInt(
      KEY_DICTIONARY_DATA_CURRENT_VERSION, latestVersion);
  print(
      "Set KEY_LAST_DICTIONARY_DATA_CHECK_TIME to $now and KEY_DICTIONARY_DATA_CURRENT_VERSION to $latestVersion. Done!");
  return true;
}

// Returns the local path where we store the dictionary data we download.
Future<File> get _dictionaryDataFilePath async {
  final path = (await getApplicationDocumentsDirectory()).path;
  return File('$path/word_dictionary.json');
}

// Load up favourites.
Future<Set<Word>> loadFavourites() async {
  Map<String, Word> keyedWordsGlobal = {};
  for (Word w in wordsGlobal) {
    keyedWordsGlobal[w.word] = w;
  }
  Set<Word> favourites = {};
  // Load up the Words for the favourites (inefficiently).
  List<String> favouritesRaw =
      sharedPreferences.getStringList(KEY_FAVOURITES_WORDS) ?? [];
  print("Loaded favourites: $favouritesRaw");
  for (String s in favouritesRaw) {
    Word? matchingWord = keyedWordsGlobal[s];
    if (matchingWord != null) {
      favourites.add(matchingWord);
    }
  }
  if (favouritesRaw.length != favourites.length) {
    // Write back the favourites, without the missing entries.
    await sharedPreferences.setStringList(
        KEY_FAVOURITES_WORDS, favourites.map((e) => e.word).toList());
    print(
        "Wrote back favourites with ${favouritesRaw.length - favourites.length} fewer words");
  }
  return favourites;
}

// Run this at startup.
Future<void> bootstrapFavourites() async {
  try {
    sharedPreferences.getStringList(KEY_FAVOURITES_WORDS);
  } catch (e) {
    // The key didn't exist in the favourites list yet.
    await sharedPreferences.setStringList(KEY_FAVOURITES_WORDS, ["love"]);
    print("Bootstrapped favourites");
  }
}

// Clear favourites.
Future<void> clearFavourites() async {
  favouritesGlobal = {};
  await sharedPreferences.setStringList(KEY_FAVOURITES_WORDS, []);
}

// Write favourites to prefs.
Future<void> writeFavourites() async {
  await sharedPreferences.setStringList(
      KEY_FAVOURITES_WORDS, favouritesGlobal.map((e) => e.word).toList());
}

// Add to favourites.
Future<void> addToFavourites(Word favouriteToAdd) async {
  favouritesGlobal.add(favouriteToAdd);
  await writeFavourites();
}

// Remove from favourites.
Future<void> removeFromFavourites(Word favouriteToRemove) async {
  favouritesGlobal.remove(favouriteToRemove);
  await writeFavourites();
}

bool getShouldUseHorizontalLayout(BuildContext context) {
  var screenSize = MediaQuery.of(context).size;
  var shouldUseHorizontalDisplay = screenSize.width > screenSize.height * 1.2;
  return shouldUseHorizontalDisplay;
}

// Reaches out to check the value of the knob. If this succeeds, we store the
// value locally. If this fails, we first check the local store to attempt to
// use the value the value we last saw for the knob. If there is nothing there,
// we use the hardcoded `fallback` value.
Future<bool> readKnob(String key, bool fallback) async {
  String sharedPrefsKey = "knob_$key";
  try {
    String url =
        'https://raw.githubusercontent.com/banool/auslan_dictionary/master/knobs/$key';
    var result = await http.get(Uri.parse(url));
    String raw = result.body.replaceAll("\n", "");
    bool out;
    if (raw == "true") {
      out = true;
    } else if (raw == "false") {
      out = false;
    } else {
      throw "Failed to check knob at $url, using fallback value: $fallback, due to ${result.body}";
    }
    await sharedPreferences.setBool(sharedPrefsKey, out);
    print("Value of knob $key is $out, stored at $sharedPrefsKey");
    return out;
  } catch (e, stacktrace) {
    print("$e:\n$stacktrace");
    var out = sharedPreferences.getBool(sharedPrefsKey) ?? fallback;
    print("Returning fallback value for knob $key: $out");
    return out;
  }
}

bool getShowFlashcards() {
  if (!enableFlashcardsKnob) {
    return false;
  }
  return !(sharedPreferences.getBool(KEY_HIDE_FLASHCARDS_FEATURE) ?? false);
}

Future<bool> confirmAlert(BuildContext context, Widget content,
    {String title = "Careful!",
    String cancelText = "Cancel",
    String confirmText = "Confirm"}) async {
  bool confirmed = false;
  Widget cancelButton = FlatButton(
    child: Text(cancelText),
    onPressed: () {
      Navigator.of(context).pop();
    },
  );
  Widget continueButton = FlatButton(
    child: Text(confirmText),
    onPressed: () {
      confirmed = true;
      Navigator.of(context).pop();
    },
  );
  AlertDialog alert = AlertDialog(
    title: Text(title),
    content: content,
    actions: [
      cancelButton,
      continueButton,
    ],
  );
  await showDialog(
    context: context,
    builder: (BuildContext context) {
      return alert;
    },
  );
  return confirmed;
}

Widget buildActionButton(
    BuildContext context, Icon icon, void Function() onPressed,
    {bool enabled = true,
    Color enabledColor = Colors.white,
    Color disabledColor = APP_BAR_DISABLED_COLOR}) {
  void Function()? onPressedFunc = onPressed;
  if (!enabled) {
    onPressedFunc = null;
  }
  return Container(
      width: 45,
      child: TextButton(
          onPressed: onPressedFunc,
          child: icon,
          style: ButtonStyle(
              padding: MaterialStateProperty.all(EdgeInsets.zero),
              shape: MaterialStateProperty.all(
                  CircleBorder(side: BorderSide(color: Colors.transparent))),
              fixedSize: MaterialStateProperty.all(Size.fromWidth(10)),
              foregroundColor: MaterialStateProperty.resolveWith(
                (states) {
                  if (states.contains(MaterialState.disabled)) {
                    return disabledColor;
                  } else {
                    return enabledColor;
                  }
                },
              ))));
}

List<Widget> buildActionButtons(List<Widget> actions) {
  actions = actions + <Widget>[Padding(padding: EdgeInsets.only(right: 5))];
  return actions;
}
