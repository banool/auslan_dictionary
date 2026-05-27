# Shared-lists setup (manual steps for the auslan_dictionary repo)

This document covers the auslan-specific platform-config steps. The cross-app setup (Cloudflare, Apple Developer, Google Cloud, Facebook, Worker secrets, Worker route bindings, Xcode entitlements) lives in **`dictionarylib/lists/MANUAL_SETUP.md`** — start there if you're standing this up from scratch or onto a new account. Xcode wiring for Associated Domains + Sign in with Apple is documented there too (§"iOS — Associated Domains" and §1a).

## Provider client identifiers in this repo

All `REPLACE_WITH_*` placeholders have been filled in. For reference, the live values are:

| Where                                         | What                                               |
|-----------------------------------------------|----------------------------------------------------|
| `ios/Runner/Info.plist` `GIDClientID`         | Google iOS OAuth client id                         |
| `ios/Runner/Info.plist` `com.googleusercontent.apps.*` URL scheme | Reversed Google iOS client id |
| `ios/Runner/Info.plist` `FacebookAppID` + `FacebookClientToken` + `fb<id>` URL scheme | Facebook app config |
| `android/app/src/main/res/values/strings.xml` `facebook_app_id` / `facebook_client_token` / `fb_login_protocol_scheme` | Facebook app config (Android) |
| `lib/main.dart` `SharingAuthConfig.appleBundleId` | iOS bundle id (camelCase)                       |
| `lib/main.dart` `SharingAuthConfig.appleServicesId` | Apple Services ID for Android web flow         |
| `lib/main.dart` `SharingAuthConfig.appleRedirectUri` | Apple's `form_post` redirect URL                |
| `lib/main.dart` `SharingAuthConfig.googleServerClientId` | Google **Web** OAuth client id — required by `google_sign_in` v7 on Android (Credential Manager mints ID tokens with the Web client as `aud`). Must appear in the Worker's `GOOGLE_AUDIENCES`. |
| `lib/main.dart` `SharingAuthConfig.facebookAppId` | Facebook app id                                 |
| `lib/main.dart` `SharingConfig.testSignIn` | Debug-only test sign-in config (token sourced from `--dart-define=TEST_AUTH_TOKEN=...`). Surfaces a "Sign in as test user" button in `kDebugMode` builds. See `dictionarylib/lists/MANUAL_SETUP.md` § "Integration testing without provider accounts". |

Provider-side provisioning (creating these clients, enabling Sign in with Apple, hosting the Facebook app secret server-side, etc.) is documented in `dictionarylib/lists/MANUAL_SETUP.md` §1–§4.

## Outstanding platform caveats

- Xcode 15 or newer is required. The iOS `project.pbxproj` was bumped to `objectVersion = 60`; older Xcode versions will refuse to open the project.
- Both SHA-256 fingerprints in `dictionarylib/lists/site/.well-known/assetlinks.json` must remain valid. One is the debug keystore, the other is the release / Play upload key — re-generating either keystore requires regenerating and re-deploying the corresponding fingerprint, otherwise Android App Link verification will fail.
- The `googleServerClientId` in `lib/main.dart` is currently the same string as the iOS `GIDClientID`. Google sign-in on Android may not work until this is replaced with the dedicated Web client id from Google Cloud Console. Verify before shipping Android.
- `SharingAuthConfig.appleServicesId` and `appleRedirectUri` are currently `null`, which disables the Android Sign in with Apple flow (the button errors gracefully rather than hitting an unprovisioned endpoint). Provision the Apple Services ID and set both before enabling Apple on Android.

## Local-only files (not committed)

- `.secrets-reference/GoogleService-Info.plist` — original iOS Google config download, kept locally for reference. Not used at runtime; the same iOS client id is wired into `Info.plist` via `GIDClientID` + URL scheme.
- `.secrets-reference/client_secret_*.json` — Android Google OAuth client secret download. Not used at runtime either; the Android `google_sign_in` plugin authenticates via Play Services + the SHA-1 registered in GCP.

Both are gitignored.

## Smoke tests on a real device

After installing a build with the wired-up manifest + entitlements:

```sh
# Android — confirm the App Link verified for share.<dictionary>
adb shell pm verify-app-links --re-verify com.banool.auslan_dictionary
adb shell pm get-app-links com.banool.auslan_dictionary

# Then tap a share URL
adb shell am start -W -a android.intent.action.VIEW \
  -d "https://share.auslandictionary.org/l/test-list"

# iOS — paste a share URL into Notes.app and tap it. No CLI equivalent.
```

Then in the app: open a list → tap Share → walk through the sign-in dialog for each provider (Apple, Google, Facebook). Each should round-trip to the Worker and return a session JWT; the share-link dialog should appear after a successful sign-in.

For end-to-end API verification with curl (using either the gated test sign-in path or real provider tokens), see `dictionarylib/lists/workers/CURL_GUIDE.md`.
