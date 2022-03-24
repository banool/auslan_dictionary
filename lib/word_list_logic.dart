import 'dart:collection';
import 'package:flutter/material.dart';

import 'globals.dart';
import 'types.dart';

const String KEY_WORD_LIST_KEYS = "word_list_keys";
const String KEY_FAVOURITES_WORDS = "favourites_words";

class WordList {
  static final validNameCharacters = RegExp(r'^[a-zA-Z0-9 ]+$');

  String key;
  LinkedHashSet<Word> words; // Ordered by insertion order.

  WordList(this.key, this.words);

  // This takes in the raw string key, pulls the list of raw strings from
  // storage, and converts them into a name and a list of words respectively.
  factory WordList.fromRaw(String key) {
    LinkedHashSet<Word> words = loadWordList(key);
    return WordList(key, words);
  }

  // Load up a word list. If the key doesn't exist, it'll just return an empty list.
  // In the empty list case, it'll write the empty list back to storage to ensure
  // it is there for next time.
  static LinkedHashSet<Word> loadWordList(String key) {
    LinkedHashSet<Word> words = LinkedHashSet();
    // Load up the Words for the favourites (inefficiently).
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

  String getName() {
    if (key == KEY_FAVOURITES_WORDS) {
      return "Favourites";
    }
    return key.substring(0, key.length - 5).replaceAll("_", " ");
  }

  Widget getLeadingIcon() {
    if (key == KEY_FAVOURITES_WORDS) {
      return Icon(
        Icons.star,
      );
    }
    return Icon(Icons.list);
  }

  bool canBeDeleted() {
    return !(key == KEY_FAVOURITES_WORDS);
  }

  static String getKeyFromName(String name) {
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
      throw "List $key already exists";
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
}
