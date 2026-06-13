import 'package:dictionarylib/dictionarylib.dart';
import 'package:dictionarylib/page_force_upgrade.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import 'common.dart';
import 'entries_loader.dart';
import 'root.dart';

const String KNOBS_URL_BASE =
    "https://raw.githubusercontent.com/banool/auslan_dictionary/master/assets/knobs/";

Future<void> setup({Set<Entry>? entriesGlobalReplacement}) async {
  var widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Initialize media_kit for video playback (native only; web plays via the
  // HTML5 video_player path — see VideoSurface in dictionarylib).
  if (!kIsWeb) {
    MediaKit.ensureInitialized();
  }

  // Preserve the splash screen while the app initializes. Native only —
  // there's no web splash configured, so calling this on web throws.
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }

  await setupPhaseOne();

  // It is okay to check for yanked versions and do phase two setup at the same
  // time because phase two setup never throws. We want to do them together
  // because they both make network calls, so we can do them concurrently.
  await Future.wait<void>([
    (() async {
      // v2 advisories file: read only by 2.0.0+ builds. Older versions have the
      // legacy assets/advisories.md URL baked in and never see anything added
      // here, which is how new announcements stay off old builds without a
      // hotfix. See assets/advisories_v2.md for the format.
      await setupPhaseTwo(Uri.parse(
          "https://raw.githubusercontent.com/banool/auslan_dictionary/master/assets/advisories_v2.md"));
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

  // One-shot migration of stored DolphinSR review history from the
  // v1 master id shape ("entryKey-firstVideoFilename") to the v2
  // shape (per-saved-video). No-op after the first successful run.
  // Must run after setupPhaseThree because it walks the dictionary
  // to resolve legacy master ids.
  await migrateLegacyReviewsIfNeeded();

  // Opt in to the shared-lists feature. Runs after phase three because the
  // synced-list manager resolves owner-share metadata against
  // userEntryListManager, which phase three initializes.
  //   apiBaseUrl     — Cloudflare Worker (JSON API)
  //   shareLinkHost  — GitHub Pages static site (where share URLs land,
  //                    where the App Link / Universal Link manifests live)
  //   auth           — OAuth client ids per provider. Each must match the
  //                    corresponding Worker env (`APPLE_AUDIENCES`,
  //                    `GOOGLE_AUDIENCES`, `FACEBOOK_APP_ID`,
  //                    `MICROSOFT_CLIENT_ID`). See
  //                    MANUAL_SETUP.md in the private backend repo.
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
      // Apple flow. Must match the Services ID registered in Apple
      // Developer Portal → Identifiers → Services IDs and the value in
      // the Worker's APPLE_AUDIENCES. Until that Services ID is
      // configured (Primary App ID + Domains + Return URLs), the
      // Android Apple button errors out with a localised "not
      // configured" message rather than completing.
      appleServicesId: 'com.banool.auslandictionarysignin',
      // The URL Apple POSTs the form_post response to. Must exactly
      // match the Return URL registered with the Services ID. The
      // Worker handles the POST and 302s to
      // https://share.auslandictionary.org/apple-callback?id_token=…
      // which the AndroidManifest intent filter catches as an App Link.
      appleRedirectUri: 'https://share.auslandictionary.org/v1/apple-callback',
      // Google OAuth **Web** client id (created 2026-06-11). Required by
      // `google_sign_in` v7 on Android: Credential Manager mints ID
      // tokens with this Web client as `aud`, so it must appear in the
      // Worker's `GOOGLE_AUDIENCES`. iOS signs in via `GIDClientID` in
      // Info.plist (the iOS client) and only uses this as the server
      // audience. The client's secret is unused — verification is
      // offline against Google's JWKS. See
      // MANUAL_SETUP.md in the private backend repo §2.
      googleServerClientId:
          '901039920141-fq7ln7rltv705srdtruuafm48d2mv38d.apps.googleusercontent.com',
      // Facebook app id from developers.facebook.com → My Apps → App ID.
      facebookAppId: '1003244748751862',
      // Microsoft Entra (Azure AD) application (client) id from the Azure
      // Portal app registration. Must match the Worker's
      // `MICROSOFT_CLIENT_ID`. One id covers iOS + Android. See
      // MANUAL_SETUP.md in the private backend repo §4.
      microsoftClientId: '9001429b-4197-45e2-8f22-1b4a6c915b46',
      // Android MSAL redirect URIs, one per signing cert (Play App
      // Signing key, upload key, debug keystore); the wrapper picks
      // whichever matches the running build's real signature. Generate
      // with android/get-sha1.sh; every hash must also be registered in
      // Azure and as a <data> entry in AndroidManifest.xml. Details:
      // MANUAL_SETUP.md in the private backend repo §4.
      microsoftAndroidRedirectUri:
          'msauth://com.banool.auslan_dictionary/tnPupvWBIsfs5VUhZbUCXxyL8%2FQ%3D',
      microsoftAndroidUploadRedirectUri:
          'msauth://com.banool.auslan_dictionary/uJIuQL8qD443LNaG3%2B5OF%2BzMYB4%3D',
      microsoftAndroidDebugRedirectUri:
          'msauth://com.banool.auslan_dictionary/mLnUCgy8ygvZ%2B2jXJtHai%2FNmrCw%3D',
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

  // Remove the splash screen (native only; see preserve above).
  if (!kIsWeb) {
    FlutterNativeSplash.remove();
  }

  // Finally run the app.
  printAndLog("Setup complete, running app");
}

Future<void> main() async {
  // Clean web URLs (e.g. /share/<id>) instead of the default hash routing, so
  // the share-link deep routes resolve. No-op on mobile.
  //
  // Deliberately a single runApp() below — NOT an early runApp() with a loading
  // screen here. A first runApp() before setup() makes Flutter's web engine
  // normalise the browser URL to "/" and clear the title before go_router and
  // MaterialApp.title read them, which dropped /share/<id> deep links onto the
  // home tab and left the tab title showing the bare URL. The web boot/loading
  // indication lives in web/index.html instead, which Flutter replaces on its
  // first frame without touching routing.
  if (kIsWeb) {
    usePathUrlStrategy();
    // go_router only reflects `go()` in the browser URL by default; `push` /
    // `replace` (which is how an entry page is opened, see navigateToEntryPage)
    // leave the URL unchanged unless this is set. Without it /word/<key> never
    // shows up in the address bar.
    GoRouter.optionURLReflectsImperativeAPIs = true;
  }
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
