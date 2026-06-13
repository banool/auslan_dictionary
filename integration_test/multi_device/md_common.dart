// Shared plumbing for the multi-device end-to-end suite.
//
// The model: two REAL app installs on two simulators/emulators, driven
// phase by phase against one local `wrangler dev` worker. Each phase is a
// normal `integration_test` run on one device; the driver script
// (`run.sh`) alternates devices and carries the invite link from the
// owner phase to the editor phase via a dart-define. Unlike
// `dictionarylib/test/sharing/multi_device_sync_test.dart` (real engine
// vs raw HTTP in one process), every actor here is the full production
// app — UI, router, platform channels, real HTTP stack — so this is the
// closest thing to two phones on a desk.
//
// Boot the whole thing with:
//   integration_test/multi_device/run.sh
//
// Dart-defines (all optional except where a phase says otherwise):
//   MD_API_BASE_URL  worker base URL. Default http://localhost:8787
//                    (host loopback — correct for iOS simulators; the
//                    driver passes http://10.0.2.2:8787 for Android).
//   MD_TEST_AUTH_TOKEN  must match the worker env's TEST_AUTH_TOKEN.
//   MD_RUN_ID        disambiguates user ids / list names across runs so
//                    leftover state from an aborted run can't collide.
//   MD_INVITE_URL    phase B only: the invite link minted in phase A.

import 'dart:convert';
import 'dart:io';

import 'package:dictionarylib/dictionarylib.dart';
import 'package:dictionarylib/l10n/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';

import 'package:auslan_dictionary/entries_loader.dart';
import 'package:auslan_dictionary/main.dart' show KNOBS_URL_BASE;
import 'package:auslan_dictionary/root.dart';

import '../helpers.dart';

const String mdApiBaseUrl = String.fromEnvironment('MD_API_BASE_URL',
    defaultValue: 'http://localhost:8787');

const String mdTestAuthToken = String.fromEnvironment('MD_TEST_AUTH_TOKEN',
    defaultValue: 'dev-integration-test-token-please-override');

const String mdRunId =
    String.fromEnvironment('MD_RUN_ID', defaultValue: 'local');

const String mdInviteUrl = String.fromEnvironment('MD_INVITE_URL');

/// Fixed identities per run. The owner lives on device A, the editor on
/// device B; later phases sign in as the same user to resume.
String get mdOwnerUserId => 'test:md-$mdRunId-owner';
String get mdEditorUserId => 'test:md-$mdRunId-editor';
const String mdOwnerName = 'Md Owner';
const String mdEditorName = 'Md Editor';

/// The list the suite drives end to end. Local list keys are
/// `<Name>_words`; the UI renders the bare name.
const String mdListKey = 'Animals_words';
const String mdListName = 'Animals';
const String mdRenamedListName = 'Animals2';

/// English strings for finding widgets — the suite always boots the app
/// with [LOCALE_ENGLISH].
final DictLibLocalizationsEn mdL10n = DictLibLocalizationsEn();

/// Must match the worker dev env's APP_ID (the backend repo's workers/wrangler.toml).
const String _appId = 'auslan';

/// Mirrors `setup()` in lib/main.dart, with two test-only differences:
/// sharing points at the local worker instead of production, and the
/// yanked-version check is skipped (a forced upgrade must not be able to
/// veto an e2e run). Keep the phase order in lockstep with main.dart.
Future<void> mdSetup() async {
  MediaKit.ensureInitialized();
  await setupPhaseOne();
  await setupPhaseTwo(Uri.parse(
      'https://raw.githubusercontent.com/banool/auslan_dictionary/master/assets/advisories.md'));
  await setupPhaseThree(
      paramEntryLoader: MyEntryLoader(), knobUrlBase: KNOBS_URL_BASE);
  await migrateLegacyReviewsIfNeeded();
  await setupSharing(const SharingConfig(
    appId: _appId,
    appName: 'Auslan Dictionary',
    apiBaseUrl: mdApiBaseUrl,
    // Production link shape so minted invite links round-trip through the
    // same parsing the share/subscribe dialogs apply to real links.
    shareLinkBaseUrl: 'https://share.auslandictionary.org/l',
    shareLinkHost: 'share.auslandictionary.org',
    urlScheme: 'auslan',
    auth: SharingAuthConfig(
      appleBundleId: 'com.banool.auslanDictionary',
      googleServerClientId: 'unused-in-md-tests',
      facebookAppId: 'unused-in-md-tests',
    ),
    testSignIn: TestSignInConfig(
      testAuthToken: mdTestAuthToken,
      defaultUserIdPrefix: 'test:md',
      defaultDisplayName: 'Md Tester',
    ),
  ));
}

/// Pump the real app and wait until the bottom navigation is up.
Future<void> mdPumpApp(WidgetTester tester) async {
  // The first-run advisory dialog would otherwise sit over the whole app
  // and swallow taps; the other integration suites suppress it the same way.
  advisoryShownOnce = true;
  await tester.pumpWidget(RootApp(startingLocale: LOCALE_ENGLISH));
  await mdWaitForUi(
      tester, () => find.byIcon(Icons.view_list).evaluate().isNotEmpty,
      reason: 'app should boot to a page with the bottom navigation');
}

/// Sign in via the worker's test provider, through the production
/// AuthService path (mints a session, persists it like any other
/// provider's). Signs out first if some other identity is resident.
Future<void> mdSignInAs(String userId, String displayName) async {
  final current = sharing.auth.store.current;
  if (current != null) {
    if (current.userId == userId) return;
    await sharing.signOut();
  }
  await sharing.auth.signInWithTestToken(
    testAuthToken: mdTestAuthToken,
    userId: userId,
    displayName: displayName,
  );
}

/// Poll [check] (which may do real IO) until it returns true, pumping the
/// UI between samples so the app keeps running. Fails the test on timeout.
Future<void> mdWaitFor(
  WidgetTester tester,
  Future<bool> Function() check, {
  required String reason,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await check()) return;
    await tester.pump(const Duration(milliseconds: 400));
  }
  fail('Timed out waiting for: $reason');
}

/// Like [mdWaitFor] but for UI state: polls a widget-tree predicate.
Future<void> mdWaitForUi(
  WidgetTester tester,
  bool Function() check, {
  required String reason,
  Duration timeout = const Duration(seconds: 20),
}) {
  return mdWaitFor(tester, () async {
    await settle(tester);
    return check();
  }, reason: reason, timeout: timeout);
}

/// Emit a key=value line for run.sh to scrape from the test output.
void mdEmit(String key, String value) {
  // ignore: avoid_print
  print('MD_OUT $key=$value');
}

Map<String, String> _authHeaders() {
  final session = sharing.auth.store.current;
  if (session == null) fail('no signed-in session for server-truth check');
  return {
    'x-app-id': _appId,
    'authorization': 'Bearer ${session.sessionToken}',
  };
}

/// Typed view of the worker's GET /v1/lists/:id/state response — just the
/// fields the suite asserts on. Decoding happens once, here, so the phase
/// tests stay free of raw-JSON casts.
class MdServerList {
  /// The list's display name as the server knows it.
  final String displayName;

  /// Entry keys in server position order.
  final List<String> entryKeys;

  /// Canonical user id (`provider:sub`) of the owner.
  final String ownerUserId;

  /// Canonical user ids of the editors.
  final List<String> editorUserIds;

  const MdServerList({
    required this.displayName,
    required this.entryKeys,
    required this.ownerUserId,
    required this.editorUserIds,
  });

  factory MdServerList.fromJson(Map<String, dynamic> json) {
    final members = json['members'] as Map<String, dynamic>;
    final owner = members['owner'] as Map<String, dynamic>;
    return MdServerList(
      displayName: json['displayName'] as String,
      entryKeys: [
        for (final e in json['entries'] as List<dynamic>)
          (e as Map<String, dynamic>)['entry'] as String,
      ],
      ownerUserId: owner['userId'] as String,
      editorUserIds: [
        for (final e in members['editors'] as List<dynamic>)
          (e as Map<String, dynamic>)['userId'] as String,
      ],
    );
  }
}

/// Server truth: authenticated GET /v1/lists/:id/state.
Future<MdServerList> mdServerState(String listId) async {
  final resp = await http.get(
    Uri.parse('$mdApiBaseUrl/v1/lists/$listId/state'),
    headers: _authHeaders(),
  );
  if (resp.statusCode != 200) {
    fail('GET /state for $listId: HTTP ${resp.statusCode} ${resp.body}');
  }
  return MdServerList.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
}

/// Entry keys currently in the list per the server, in position order.
Future<List<String>> mdServerEntryKeys(String listId) async =>
    (await mdServerState(listId)).entryKeys;

/// True when the worker is reachable; used to fail fast with a clear
/// message instead of timing out widget-by-widget.
Future<void> mdRequireServer() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final req = await client.getUrl(Uri.parse('$mdApiBaseUrl/v1/health'));
    final resp = await req.close().timeout(const Duration(seconds: 5));
    await resp.drain<void>();
    if (resp.statusCode != 200) {
      fail('worker at $mdApiBaseUrl unhealthy: HTTP ${resp.statusCode}');
    }
  } catch (e) {
    fail('no worker reachable at $mdApiBaseUrl — start one with: '
        "bash -c 'cd dictionary_backend/workers && bunx wrangler dev --env dev' "
        '($e)');
  } finally {
    client.close(force: true);
  }
}

/// Wait for [finder] to match, then tap its first match.
Future<void> mdTapWhenVisible(WidgetTester tester, Finder finder,
    {required String reason}) async {
  await mdWaitForUi(tester, () => finder.evaluate().isNotEmpty, reason: reason);
  await tester.tap(finder.first);
  await settle(tester);
}

/// A bottom-navigation tab icon. All four tab subtrees stay mounted, so a
/// bare byIcon can match an offstage twin inside a tab body (e.g. the
/// search field's magnifier) — scope to the nav bar.
Finder mdNavIcon(IconData icon) => find.descendant(
    of: find.byType(BottomNavigationBar), matching: find.byIcon(icon));

/// Open the Lists tab from anywhere in the app.
Future<void> mdOpenListsTab(WidgetTester tester) async {
  await mdTapWhenVisible(tester, mdNavIcon(Icons.view_list),
      reason: 'Lists tab icon in the bottom navigation');
}

/// Switch to a lists-overview tab by its visible label.
Future<void> mdOpenOverviewTab(WidgetTester tester, String label) async {
  await mdTapWhenVisible(tester, find.text(label),
      reason: 'lists overview tab "$label"');
}

/// Find an entry (with at least one video) whose key is none of [exclude].
/// Deterministic: first match in iteration order.
Entry mdEntryWithVideo({Set<String> exclude = const {}}) {
  return entriesGlobal.firstWhere((e) =>
      !exclude.contains(e.getKey()) &&
      e.getSubEntries().any((s) => s.getMedia().isNotEmpty));
}
