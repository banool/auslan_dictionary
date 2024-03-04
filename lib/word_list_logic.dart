import 'dart:collection';
import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/globals.dart';

const String KEY_WORD_LIST_KEYS = "word_list_keys";

// This class does not deal with list names at all, only with keys.
class MyEntryListManager {
  LinkedHashMap<String, EntryList> entryLists; // Maintains insertion order.

  MyEntryListManager(this.entryLists);

  factory MyEntryListManager.fromStartup() {
    List<String> entryListKeys =
        sharedPreferences.getStringList(KEY_WORD_LIST_KEYS) ??
            [KEY_FAVOURITES_ENTRIES];
    LinkedHashMap<String, EntryList> entryLists = LinkedHashMap();
    for (String key in entryListKeys) {
      entryLists[key] = EntryList.fromRaw(key);
    }
    return MyEntryListManager(entryLists);
  }

  Future<void> createMyEntryList(String key) async {
    if (entryLists.containsKey(key)) {
      throw "List already exists";
    }
    entryLists[key] = EntryList.fromRaw(key);
    await entryLists[key]!.write();
    await writeMyEntryListKeys();
  }

  Future<void> deleteMyEntryList(String key) async {
    entryLists.remove(key);
    await sharedPreferences.remove(key);
    await writeMyEntryListKeys();
  }

  Future<void> writeMyEntryListKeys() async {
    await sharedPreferences.setStringList(
        KEY_WORD_LIST_KEYS, entryLists.keys.toList());
  }

  // Given an item that moved from index prev to index current,
  // reorder the lists and persist that. Deny reordering the favourites.
  void reorder(int prev, int updated) {
    if (prev == 0 || updated == 0) {
      printAndLog("Refusing to reorder with favourites list: $prev and $updated");
      return;
    }
    print("Moving item from $prev to $updated");

    MapEntry<String, EntryList> toMove = entryLists.entries.toList()[prev];

    LinkedHashMap<String, EntryList> modifiedList = LinkedHashMap();
    int i = 0;
    for (MapEntry<String, EntryList> e in entryLists.entries) {
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

    entryLists = modifiedList;
  }
}
