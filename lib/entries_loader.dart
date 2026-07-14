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
    // Cloudflare R2 mirror (cdn.auslandictionary.org), populated by the
    // mirror-to-r2 CI job. Secondary fallback for the data files when GitHub
    // raw is unavailable. Replaced the old GCS bucket
    // (storage.googleapis.com/auslan-media-bucket/sync).
    'https://cdn.auslandictionary.org/data',
  ];

  // data-v2.json stores media as paths (not full URLs) — see entries_types.dart
  // + the AUSLAN_MEDIA_BASE_URL the app ships. Old app builds keep reading
  // data.json. A fresh cache name (below) makes a just-upgraded build ignore
  // its old full-URL cache and re-download data-v2.json, so the list migration
  // and the player only ever see path-based data.
  static const String dataFileName = 'data-v2.json';

  @override
  String get dictionaryCacheFileName => 'word_dictionary_v2.json';

  @override
  String get webDictionaryCacheKey => 'web_dictionary_data_v2';

  @override
  Future<NewData?> downloadNewData(
      int currentVersion, bool forceDownload) async {
    printAndLog("Fetching latest version of data");

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
        String newData =
            (await http.get(Uri.parse('$baseUrl/$dataFileName'))).body;

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
    final raw = json.decode(data) as Map<String, dynamic>;
    Set<MyEntry> entries = {};
    for (final entry in raw["data"] as List<dynamic>) {
      entries.add(MyEntry.fromJson(entry as Map<String, dynamic>));
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
