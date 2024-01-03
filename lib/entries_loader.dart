import 'dart:convert';

import 'package:dictionarylib/entry_loader.dart';
import 'package:http/http.dart' as http;

import 'entries_types.dart';

class MyEntryLoader extends EntryLoader {
  @override
  Future<NewData?> downloadNewData(int currentVersion) async {
    int latestVersion = int.parse((await http.get(Uri.parse(
            'https://raw.githubusercontent.com/banool/auslan_dictionary/master/assets/data/latest_version')))
        .body);

    if (latestVersion <= currentVersion) {
      print(
          "Current version ($currentVersion) is >= latest version ($latestVersion), not downloading new data");
      return null;
    }

    // At this point, we know we need to download the new data. Let's do that.
    String newData = (await http.get(Uri.parse(
            'https://raw.githubusercontent.com/banool/auslan_dictionary/master/assets/data/words_latest.json')))
        .body;

    return NewData(newData, latestVersion);
  }

  @override
  Set<MyEntry> loadEntriesInner(String data) {
    dynamic wordsJson = json.decode(data);
    Set<MyEntry> words = {};
    for (MapEntry e in wordsJson.entries) {
      words.add(MyEntry.fromJson(e.key, e.value));
    }
    print("Loaded ${words.length} words");
    return words;
  }
}
