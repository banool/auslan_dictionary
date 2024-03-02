import 'dart:convert';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list_categories.dart';
import 'package:dictionarylib/entry_loader.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
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
    } else {
      print(
          "Current version ($currentVersion) is < latest version ($latestVersion), downloading new data");
    }

    // At this point, we know we need to download the new data. Let's do that.
    String newData = (await http.get(Uri.parse(
            'https://raw.githubusercontent.com/banool/auslan_dictionary/master/assets/data/data.json')))
        .body;

    return NewData(newData, latestVersion);
  }

  @override
  Set<MyEntry> loadEntriesInner(String data) {
    dynamic raw = json.decode(data);
    Set<MyEntry> entries = {};
    for (var entry in raw["data"]) {
      entries.add(MyEntry.fromJson(entry));
    }
    print("Loaded ${entries.length} words");
    return entries;
  }

  @override
  setEntriesGlobal(Set<Entry> entries) {
    super.setEntriesGlobal(entries);

    // Update the entry list manager that is based on category. Just by setting
    // this the app should show the community entry lists.
    communityEntryListManager = CategoryEntryListManager.fromStartup();
    printAndLog("Built community entry list manager");
  }
}
