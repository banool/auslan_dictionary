import 'package:dictionarylib/dictionarylib.dart';
import 'package:dictionarylib/page_force_upgrade.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:media_kit/media_kit.dart';

import 'common.dart';
import 'entries_loader.dart';
import 'root.dart';

const String KNOBS_URL_BASE =
    "https://raw.githubusercontent.com/banool/auslan_dictionary/master/assets/knobs/";

Future<void> setup({Set<Entry>? entriesGlobalReplacement}) async {
  var widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Initialize media_kit for video playback.
  MediaKit.ensureInitialized();

  // Preserve the splash screen while the app initializes.
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await setupPhaseOne();

  // It is okay to check for yanked versions and do phase two setup at the same
  // time because phase two setup never throws. We want to do them together
  // because they both make network calls, so we can do them concurrently.
  await Future.wait<void>([
    (() async {
      await setupPhaseTwo(Uri.parse(
          "https://raw.githubusercontent.com/banool/auslan_dictionary/master/assets/advisories.md"));
    })(),
    (() async {
      // If the user needs to upgrade, this will throw a specific error that main()
      // can catch to show the ForceUpgradePage.
      await GitHubYankedVersionChecker(
              "https://raw.githubusercontent.com/banool/auslan_dictionary/master/assets/yanked_versions")
          .throwIfShouldUpgrade();
    })(),
  ]);

  MyEntryLoader myEntryLoader = MyEntryLoader();

  await setupPhaseThree(
      paramEntryLoader: myEntryLoader,
      knobUrlBase: KNOBS_URL_BASE,
      entriesGlobalReplacement: entriesGlobalReplacement);

  // Opt in to the shared-lists feature. Runs after phase three because the
  // synced-list manager resolves owner-share metadata against
  // userEntryListManager, which phase three initializes.
  //   apiBaseUrl     — Cloudflare Worker (JSON API)
  //   shareLinkHost  — GitHub Pages static site (where share URLs land,
  //                    where the App Link / Universal Link manifests live)
  //   auth           — OAuth client ids per provider. Each must match the
  //                    corresponding Worker env (`APPLE_AUDIENCES`,
  //                    `GOOGLE_AUDIENCES`, `FACEBOOK_APP_ID`). See
  //                    dictionarylib/lists/MANUAL_SETUP.md.
  await setupSharing(const SharingConfig(
    appId: 'auslan',
    appName: 'Auslan Dictionary',
    apiBaseUrl: 'https://api.auslandictionary.org',
    shareLinkBaseUrl: 'https://share.auslandictionary.org/l',
    shareLinkHost: 'share.auslandictionary.org',
    urlScheme: 'auslan',
    auth: SharingAuthConfig(
      // Real iOS bundle id (camelCase). Different from the Android
      // package name (snake_case) — that's a historical artifact and
      // each platform expects its own identifier.
      appleBundleId: 'com.banool.auslanDictionary',
      // Apple Services ID (Web auth) used by the Android Sign in with
      // Apple flow. The Android Apple flow is disabled until the
      // Services ID is provisioned in Apple Developer Portal →
      // Identifiers → Services IDs and verified end-to-end. Set both
      // appleServicesId and appleRedirectUri together once ready;
      // until then the Android Apple button errors out gracefully
      // with a localised "not configured" message rather than
      // hitting an unprovisioned endpoint.
      //
      // appleRedirectUri is the URL Apple POSTs the form_post response
      // to. It must match the Return URL registered with the Services
      // ID. The Worker handles the POST and 302s to
      // https://share.auslandictionary.org/apple-callback?id_token=…
      // which the AndroidManifest intent filter catches as an App Link.
      appleServicesId: null,
      appleRedirectUri: null,
      // Google OAuth **Web** client id. Required by `google_sign_in` v7
      // on Android (Credential Manager mints ID tokens with the Web
      // client as `aud`). Must appear in the Worker's
      // `GOOGLE_AUDIENCES`. See dictionarylib/lists/MANUAL_SETUP.md §2.
      //
      // TODO: The value below is currently the same as the iOS client
      // id (`GIDClientID` in ios/Runner/Info.plist + the reversed-
      // client-id URL scheme on line ~44). If Google strictly enforces
      // distinct client ids per platform, Android sign-in will fail
      // at runtime — replace with the dedicated **Web** client id
      // from Google Cloud Console before shipping Android.
      googleServerClientId:
          '901039920141-ag39tbgmhje86jq3rtsdbnec8j3flrp6.apps.googleusercontent.com',
      // Facebook app id from developers.facebook.com → My Apps → App ID.
      facebookAppId: '1003244748751862',
    ),
    // Debug-only "Sign in as test user" button. Visible only in
    // kDebugMode AND when testAuthToken is non-empty. Token must be
    // passed explicitly via `--dart-define=TEST_AUTH_TOKEN=...` —
    // the default empty string keeps the affordance disabled so no
    // shared token can leak into release builds. The token must
    // match the `wrangler dev` (or staging) env's `TEST_AUTH_TOKEN`.
    testSignIn: TestSignInConfig(
      testAuthToken: String.fromEnvironment(
        'TEST_AUTH_TOKEN',
        defaultValue: '',
      ),
      defaultUserIdPrefix: 'test:auslan-dev',
      defaultDisplayName: 'Auslan Tester',
    ),
  ));

  // Remove the splash screen.
  FlutterNativeSplash.remove();

  // Finally run the app.
  printAndLog("Setup complete, running app");
}

Future<void> main() async {
  printAndLog("Start of main");
  try {
    await setup();
    runApp(RootApp(startingLocale: LOCALE_ENGLISH));
  } on YankedVersionError catch (e) {
    runApp(ForceUpgradePage(
        error: e, iOSAppId: IOS_APP_ID, androidAppId: ANDROID_APP_ID));
  } catch (error, stackTrace) {
    runApp(ErrorFallback(
      appName: APP_NAME,
      error: error,
      stackTrace: stackTrace,
    ));
  }
}
