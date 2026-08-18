import 'dart:convert';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/data_fetch.dart';
import 'package:dictionarylib/entry_list_categories.dart';
import 'package:dictionarylib/entry_loader.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;

import 'entries_types.dart';

// Debug-only override for the data hosts, e.g. to point the app at a local
// throttled/failing server to exercise the cold-start loading and error
// screens. Comma-separated base URLs. Set via --dart-define, defaults to
// empty when absent, and is ignored entirely outside debug builds — release
// builds always use [MyEntryLoader.defaultBaseUrls]. Example:
//   flutter run --dart-define=DEBUG_DATA_BASE_URLS=http://127.0.0.1:8123/data
const String _kDebugDataBaseUrls = String.fromEnvironment(
  'DEBUG_DATA_BASE_URLS',
);

class MyEntryLoader extends EntryLoader {
  static const List<String> defaultBaseUrls = [
    'https://raw.githubusercontent.com/banool/auslan_dictionary/master/assets/data',
    // Cloudflare R2 mirror (cdn.auslandictionary.org), populated by the
    // mirror-to-r2 CI job. Secondary fallback for the data files when GitHub
    // raw is unavailable. Replaced the old GCS bucket
    // (storage.googleapis.com/auslan-media-bucket/sync).
    'https://cdn.auslandictionary.org/data',
  ];

  List<String> get baseUrls => kDebugMode && _kDebugDataBaseUrls.isNotEmpty
      ? _kDebugDataBaseUrls.split(',')
      : defaultBaseUrls;

  /// Injectable for tests; null means fetchWithProgress creates (and closes)
  /// its own client per request.
  final http.Client? client;

  MyEntryLoader({this.client});

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
    int currentVersion,
    bool forceDownload, {
    Duration requestTimeout = kDataFetchTimeout,
  }) async {
    printAndLog("Fetching latest version of data");

    // Try each base URL until one works. Every request is bounded (headers +
    // body-stall, see fetchWithProgress) so a blackholed host falls through to
    // the mirror in requestTimeout rather than hanging on the OS TCP timeout,
    // and status updates feed the cold-start loading screen.
    final urls = baseUrls;
    for (final (urlIndex, baseUrl) in urls.indexed) {
      printAndLog("Trying base URL $baseUrl");
      try {
        final versionUrl = Uri.parse('$baseUrl/latest_version');
        reportDownloadStatus(
          DictionaryDownloadStatus(
            stage: DictionaryDownloadStage.checking,
            url: versionUrl,
            urlIndex: urlIndex,
            urlCount: urls.length,
          ),
        );
        final versionResult = await fetchWithProgress(
          versionUrl,
          client: client,
          headersTimeout: requestTimeout,
          stallTimeout: requestTimeout,
        );
        if (versionResult.statusCode != 200) {
          // Treated the same as any network failure: fall through to the next
          // base URL. Also guards against captive portals serving a 200-page
          // for everything — those fail the int.parse below.
          throw Exception(
            "Fetching latest_version returned HTTP ${versionResult.statusCode}",
          );
        }
        int latestVersion = int.parse(versionResult.body.trim());
        printAndLog("Fetched latest version of data: $latestVersion");

        if (!forceDownload && latestVersion <= currentVersion) {
          printAndLog(
            "Current version ($currentVersion) is >= latest version ($latestVersion), not downloading new data",
          );
          return null;
        }

        if (forceDownload) {
          printAndLog(
            "Forcing download of new data, even if the latest version is no newer than the current version. Current version: $currentVersion. Latest version: $latestVersion",
          );
        } else {
          printAndLog(
            "Current version ($currentVersion) is < latest version ($latestVersion), downloading new data",
          );
        }

        // Download the new data.
        final dataUrl = Uri.parse('$baseUrl/$dataFileName');
        final dataResult = await fetchWithProgress(
          dataUrl,
          client: client,
          headersTimeout: requestTimeout,
          stallTimeout: requestTimeout,
          onProgress: (receivedBytes, totalBytes) => reportDownloadStatus(
            DictionaryDownloadStatus(
              stage: DictionaryDownloadStage.downloading,
              url: dataUrl,
              urlIndex: urlIndex,
              urlCount: urls.length,
              receivedBytes: receivedBytes,
              totalBytes: totalBytes,
            ),
          ),
        );
        if (dataResult.statusCode != 200) {
          throw Exception(
            "Fetching $dataFileName returned HTTP ${dataResult.statusCode}",
          );
        }

        printAndLog("Successfully downloaded new data from $baseUrl");

        // If we get here, both requests succeeded
        return NewData(dataResult.body, currentVersion, latestVersion);
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
