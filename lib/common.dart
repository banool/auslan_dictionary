import 'dart:collection';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:edit_distance/edit_distance.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'types.dart';
import 'word_page.dart';

const String APP_NAME = "Auslan Dictionary";

const Color MAIN_COLOR = Colors.blue;

const String KEY_SHOULD_CACHE = "shouldCache";

const String KEY_FAVOURITES_WORDS = "favourites_words";

Future<void> navigateToWordPage(
    BuildContext context, Word word, List<Word> allWords) {
  return Navigator.push(
    context,
    MaterialPageRoute(
        builder: (context) => WordPage(word: word, allWords: allWords)),
  );
}

// Search a list of words and return top matching items.
List<Word> searchList(
    String searchTerm, List<Word> words, List<Word> fallback) {
  final SplayTreeMap<double, List<Word>> st =
      SplayTreeMap<double, List<Word>>();
  if (searchTerm == "") {
    return fallback;
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
Future<void> bootstrapFavourites() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  try {
    prefs.getStringList(KEY_FAVOURITES_WORDS);
  } catch (e) {
    // The key didn't exist in the favourites list yet.
    prefs.setStringList(KEY_FAVOURITES_WORDS, ["love"]);
    print("Bootstrapped favourites");
  }
}

// Load up favourites.
Future<List<Word>> loadFavourites(
    List<Word> words, BuildContext context) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  List<Word> favourites = [];
  // Load up the Words for the favourites (inefficiently).
  List<String> favouritesRaw = prefs.getStringList(KEY_FAVOURITES_WORDS) ?? [];
  print("Loaded favourites: $favouritesRaw");
  for (String s in favouritesRaw) {
    Word? matchingWord = words.firstWhereOrNull((element) => element.word == s);
    if (matchingWord != null) {
      favourites.add(matchingWord);
    } else {
      Scaffold.of(context).showSnackBar(SnackBar(
          content: Text(
              'Your favourite "$matchingWord" is no longer in the dictionary'),
          backgroundColor: MAIN_COLOR));
    }
  }
  // Write back the favourites, without the missing entries.
  List<String> newFavourites = [];
  for (Word w in favourites) {
    newFavourites.add(w.word);
  }
  prefs.setStringList(KEY_FAVOURITES_WORDS, newFavourites);
  return favourites;
}

// Write favourites to prefs.
void writeFavourites(List<Word?> favourites, SharedPreferences prefs) {
  List<String> newFavourites = [];
  for (Word? w in favourites) {
    newFavourites.add(w!.word);
  }
  prefs.setStringList(KEY_FAVOURITES_WORDS, newFavourites);
}

// Add to favourites.
Future<void> addToFavourites(
    Word favouriteToAdd, List<Word> words, BuildContext context) async {
  List<Word> favourites = await loadFavourites(words, context);
  favourites.add(favouriteToAdd);
  SharedPreferences prefs = await SharedPreferences.getInstance();
  writeFavourites(favourites, prefs);
}

// Remove from favourites.
Future<void> removeFromFavourites(
    Word favouriteToRemove, List<Word> words, BuildContext context) async {
  List<Word> favourites = await loadFavourites(words, context);
  favourites.removeWhere((element) => element.word == favouriteToRemove.word);
  SharedPreferences prefs = await SharedPreferences.getInstance();
  writeFavourites(favourites, prefs);
}
