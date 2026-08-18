import 'package:auslan_dictionary/entries_loader.dart';
import 'package:dictionarylib/data_fetch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const primaryHost = 'raw.githubusercontent.com';
const mirrorHost = 'cdn.auslandictionary.org';

void main() {
  test('downloads from the primary when it works', () async {
    final requested = <Uri>[];
    final loader = MyEntryLoader(
      client: MockClient((request) async {
        requested.add(request.url);
        if (request.url.path.endsWith('latest_version')) {
          return http.Response('100', 200);
        }
        return http.Response('{"data": []}', 200);
      }),
    );

    final newData = await loader.downloadNewData(50, false);
    expect(newData, isNotNull);
    expect(newData!.data, '{"data": []}');
    expect(newData.newVersion, 100);
    expect(requested.every((url) => url.host == primaryHost), true);
  });

  test(
    'an up-to-date version means no data request (when not forced)',
    () async {
      final requested = <Uri>[];
      final loader = MyEntryLoader(
        client: MockClient((request) async {
          requested.add(request.url);
          return http.Response('100', 200);
        }),
      );

      final newData = await loader.downloadNewData(100, false);
      expect(newData, null);
      expect(requested.length, 1);
      expect(requested.single.path, endsWith('latest_version'));
    },
  );

  test('forceDownload downloads even when the version is current', () async {
    final loader = MyEntryLoader(
      client: MockClient((request) async {
        if (request.url.path.endsWith('latest_version')) {
          return http.Response('100', 200);
        }
        return http.Response('{"data": []}', 200);
      }),
    );

    final newData = await loader.downloadNewData(100, true);
    expect(newData, isNotNull);
  });

  test('falls through to the mirror when the primary 500s', () async {
    final requested = <Uri>[];
    final loader = MyEntryLoader(
      client: MockClient((request) async {
        requested.add(request.url);
        if (request.url.host == primaryHost) {
          return http.Response('oh no', 500);
        }
        if (request.url.path.endsWith('latest_version')) {
          return http.Response('100', 200);
        }
        return http.Response('{"data": []}', 200);
      }),
    );

    final newData = await loader.downloadNewData(50, true);
    expect(newData, isNotNull);
    expect(requested.map((url) => url.host), [
      primaryHost, // latest_version → 500, mirror next
      mirrorHost,
      mirrorHost,
    ]);
  });

  test(
    'a captive-portal-style 200 with garbage falls through to the mirror',
    () async {
      final requested = <Uri>[];
      final loader = MyEntryLoader(
        client: MockClient((request) async {
          requested.add(request.url);
          if (request.url.host == primaryHost) {
            // A captive portal answers everything with its login page.
            return http.Response('<html>Sign in to WiFi</html>', 200);
          }
          if (request.url.path.endsWith('latest_version')) {
            return http.Response('100', 200);
          }
          return http.Response('{"data": []}', 200);
        }),
      );

      final newData = await loader.downloadNewData(50, true);
      expect(newData, isNotNull);
      expect(requested.last.host, mirrorHost);
    },
  );

  test('a non-200 on the data file falls through to the mirror', () async {
    final requested = <Uri>[];
    final loader = MyEntryLoader(
      client: MockClient((request) async {
        requested.add(request.url);
        if (request.url.path.endsWith('latest_version')) {
          return http.Response('100', 200);
        }
        if (request.url.host == primaryHost) {
          return http.Response('missing', 404);
        }
        return http.Response('{"data": []}', 200);
      }),
    );

    final newData = await loader.downloadNewData(50, true);
    expect(newData, isNotNull);
    expect(requested.map((url) => url.host), [
      primaryHost,
      primaryHost, // data file → 404, mirror next (starting from its own check)
      mirrorHost,
      mirrorHost,
    ]);
  });

  test('throws when every base URL fails', () async {
    final loader = MyEntryLoader(
      client: MockClient((request) async => http.Response('nope', 503)),
    );

    await expectLater(loader.downloadNewData(50, true), throwsException);
  });

  test('reports checking then downloading statuses with byte counts', () async {
    final loader = MyEntryLoader(
      client: MockClient((request) async {
        if (request.url.path.endsWith('latest_version')) {
          return http.Response('100', 200);
        }
        return http.Response('{"data": []}', 200);
      }),
    );

    final statuses = <DictionaryDownloadStatus?>[];
    loader.downloadStatusNotifier.addListener(
      () => statuses.add(loader.downloadStatusNotifier.value),
    );

    await loader.downloadNewData(50, true);

    expect(statuses.first!.stage, DictionaryDownloadStage.checking);
    expect(statuses.first!.urlCount, 2);
    final downloading = statuses
        .where((s) => s?.stage == DictionaryDownloadStage.downloading)
        .toList();
    expect(downloading, isNotEmpty);
    expect(downloading.last!.receivedBytes, '{"data": []}'.length);
  });
}
