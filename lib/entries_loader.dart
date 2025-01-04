import 'dart:convert';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list_categories.dart';
import 'package:dictionarylib/entry_loader.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:http/http.dart' as http;

import 'entries_types.dart';

class MyEntryLoader extends EntryLoader {
  static const List<String> baseUrls = [
    'https://raw.githubusercontent.com/banool/auslan_dictionary/master/assets/data',
    'https://storage.googleapis.com/auslan-media-bucket/sync',
  ];

  @override
  Future<NewData?> downloadNewData(
      int currentVersion, bool forceDownload) async {
    print("Fetching latest version of data");

    // Try each base URL until one works
    for (var baseUrl in baseUrls) {
      printAndLog("Trying base URL $baseUrl");
      try {
        int latestVersion = int.parse(
            (await http.get(Uri.parse('$baseUrl/latest_version'))).body);
        printAndLog("Fetched latest version of data: $latestVersion");

        if (!forceDownload && latestVersion <= currentVersion) {
          printAndLog(
              "Current version ($currentVersion) is >= latest version ($latestVersion), not downloading new data");
          return null;
        }

        if (forceDownload) {
          printAndLog(
              "Forcing download of new data, even if the latest version is no newer than the current version. Current version: $currentVersion. Latest version: $latestVersion");
        } else {
          printAndLog(
              "Current version ($currentVersion) is < latest version ($latestVersion), downloading new data");
        }

        // Download the new data
        String newData = (await http.get(Uri.parse('$baseUrl/data.json'))).body;

        printAndLog("Successfully downloaded new data from $baseUrl");

        // If we get here, both requests succeeded
        return NewData(newData, currentVersion, latestVersion);
      } catch (e) {
        printAndLog("Failed to fetch from $baseUrl: $e");
      }
    }

    printAndLog("Failed to fetch data from all base URLs");
    throw Exception("Failed to fetch data from all base URLs");
  }

  @override
  Set<MyEntry> loadEntriesInner(String data) {
    dynamic raw = json.decode(data);
    Set<MyEntry> entries = {};
    for (var entry in raw["data"]) {
      entries.add(MyEntry.fromJson(entry));
    }
    printAndLog("Loaded ${entries.length} entries");
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
