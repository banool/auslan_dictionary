import 'dart:collection';
import 'package:flutter/material.dart';

import 'common.dart';
import 'globals.dart';
import 'types.dart';

const String KEY_WORD_LIST_KEYS = "word_list_keys";

class WordList {
  static final validNameCharacters = RegExp(r'^[a-zA-Z0-9 ]+$');

  String key;
  LinkedHashSet<Word> words; // Ordered by insertion order.

  WordList(this.key, this.words);

  @override
  String toString() {
    return this.getName();
  }

  // This takes in the raw string key, pulls the list of raw strings from
  // storage, and converts them into a name and a list of words respectively.
  factory WordList.fromRaw(String key) {
    LinkedHashSet<Word> words = loadWordList(key);
    return WordList(key, words);
  }

  // Load up a word list. If the key doesn't exist, it'll just return an empty list.
  static LinkedHashSet<Word> loadWordList(String key) {
    LinkedHashSet<Word> words = LinkedHashSet();
    List<String> wordsRaw = sharedPreferences.getStringList(key) ?? [];
    print("Loaded raw words: $wordsRaw");
    for (String s in wordsRaw) {
      Word? matchingWord = keyedWordsGlobal[s];
      if (matchingWord != null) {
        words.add(matchingWord);
      } else {
        // In this case, the next time the user alters this list, the missing
        // words will be removed from storage permanently. Otherwise we'll keep
        // filtering them out, which is no big deal.
        print('Word "$s" in word list $key is no longer in the dictionary');
      }
    }
    return words;
  }

  Widget getLeadingIcon({bool inEditMode = false}) {
    if (key == KEY_FAVOURITES_WORDS) {
      return Icon(
        Icons.star,
      );
    }
    if (inEditMode) {
      return Icon(Icons.drag_handle);
    } else {
      return Icon(Icons.list_alt);
    }
  }

  bool canBeDeleted() {
    return !(key == KEY_FAVOURITES_WORDS);
  }

  static String getNameFromKey(String key) {
    if (key == KEY_FAVOURITES_WORDS) {
      return "Favourites";
    }
    return key.substring(0, key.length - 6).replaceAll("_", " ");
  }

  String getName() {
    return WordList.getNameFromKey(key);
  }

  static String getKeyFromName(String name) {
    if (name.length == 0) {
      throw "List name cannot be empty";
    }
    if (!validNameCharacters.hasMatch(name)) {
      throw "Invalid name, this should have been caught already";
    }
    return "${name}_words".replaceAll(" ", "_");
  }

  Future<void> write() async {
    await sharedPreferences.setStringList(
        key, words.map((e) => e.word).toList());
  }

  Future<void> addWord(Word wordToAdd) async {
    words.add(wordToAdd);
    await write();
  }

  Future<void> removeWord(Word wordToAdd) async {
    words.remove(wordToAdd);
    await write();
  }
}

// This class does not deal with list names at all, only with keys.
class WordListManager {
  LinkedHashMap<String, WordList> wordLists; // Maintains insertion order.

  WordListManager(this.wordLists);

  factory WordListManager.fromStartup() {
    List<String> wordListKeys =
        sharedPreferences.getStringList(KEY_WORD_LIST_KEYS) ??
            [KEY_FAVOURITES_WORDS];
    LinkedHashMap<String, WordList> wordLists = LinkedHashMap();
    for (String key in wordListKeys) {
      wordLists[key] = WordList.fromRaw(key);
    }
    return WordListManager(wordLists);
  }

  Future<void> createWordList(String key) async {
    if (wordLists.containsKey(key)) {
      throw "List already exists";
    }
    wordLists[key] = WordList.fromRaw(key);
    await wordLists[key]!.write();
    await writeWordListKeys();
  }

  Future<void> deleteWordList(String key) async {
    wordLists.remove(key);
    await sharedPreferences.remove(key);
    await writeWordListKeys();
  }

  Future<void> writeWordListKeys() async {
    await sharedPreferences.setStringList(
        KEY_WORD_LIST_KEYS, wordLists.keys.toList());
  }

  // Given an item that moved from index prev to index current,
  // reorder the lists and persist that. Deny reordering the favourites.
  void reorder(int prev, int updated) {
    if (prev == 0 || updated == 0) {
      print("Refusing to reorder with favourites list: $prev and $updated");
      return;
    }
    print("Moving item from $prev to $updated");

    MapEntry<String, WordList> toMove = wordLists.entries.toList()[prev];

    LinkedHashMap<String, WordList> modifiedList = LinkedHashMap();
    int i = 0;
    for (MapEntry<String, WordList> e in wordLists.entries) {
      if (i == prev) {
        i += 1;
        continue;
      }
      if (i == updated) {
        modifiedList[toMove.key] = toMove.value;
      }
      modifiedList[e.key] = e.value;
      i += 1;
    }

    if (!modifiedList.containsKey(toMove.key)) {
      modifiedList[toMove.key] = toMove.value;
    }

    wordLists = modifiedList;
  }
}
