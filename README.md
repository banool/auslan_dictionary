# Auslan Dictionary

This repo contains all the code for Auslan Dictionary, the free forever video dictionary and revision tool for Australian sign language.

As of 2025-01-05 the app has been downloaded 372,975 times:
- Apple: 351k (based on First-Time Downloads)
  - Desktop / Laptop: 71%
  - iPhone: 26%
  - iPad: 3%
- Android: 21.8k

Note that 67% of downloads on Apple are [institutional](https://apple.stackexchange.com/a/428958), likely implying use by educational institutions. Ignoring those, there have been 103k unique downloads.

## Releasing

There are two operations: **upload** a build (produces an *internal* build) and **promote** an already-uploaded build to a wider audience (beta testers, then the public). The commands are the same across all three of my apps; they wrap canonical scripts in the [appci](https://github.com/banool/appci) repo (checked out as a sibling of this repo, or point at it with `APPCI_DIR`).

### 1. Upload a build (internal)

- **Automatic (both platforms).** Every push that changes the app is built and uploaded by CI (`.github/workflows/ci.yaml`): a signed appbundle to the Play **internal** track (shared `app-release-android.yaml`) and an archive to the **internal** TestFlight track (shared `app-release-ios.yaml`, on a macOS runner). Nothing to run by hand.
- **Manually** (e.g. to iterate without a push): make sure `ios/secrets.env` is configured (see [App Store Connect API key](#app-store-connect-api-key-iossecretsenv)), then run `./ios/upload.sh` and/or `./android/upload.sh`.
  ```
  flutter pub get
  flutter pub run flutter_launcher_icons:main
  flutter pub run flutter_native_splash:create
  ./ios/upload.sh
  ```
  `ios/upload.sh` is fully hands-off: it verifies the API key, runs a version preflight against the store, clears any revoked/expired certs and stale provisioning profiles, then builds with `xcodebuild` using **automatic** signing and uploads to TestFlight via `xcrun altool`. With an Admin API key, automatic signing creates and manages the distribution certificate and the App Store provisioning profile (including the Sign In with Apple + Associated Domains entitlements) — no fastlane, match, Xcode GUI, or manual cert management. The build lands as an **internal** TestFlight build; `upload.sh` does not release it any further. `android/upload.sh` is the Android counterpart: preflight, `flutter build appbundle` (signed via `android/key.properties` → the keystore in `~/creds`), upload to the Play internal track.

### 2. Promote a build (beta → public)

Promotion takes an already-uploaded internal build and sends it wider. It always needs release notes, and it works on **both** platforms via a mandatory `--stage`.

**Locally** (both platforms at once):
```
./promote.sh --stage beta        # -> TestFlight "Beta Group" + Play beta track ("What to Test")
./promote.sh --stage external    # -> App Store + Play production ("What's New")
```
Pass a notes file (`./promote.sh --stage external notes.txt`) for the release notes; `--stage external` falls back to a generic default, `--stage beta` prompts you for the required "What to Test" notes. Useful flags: `--dry-run` (plan only), `--ios-only` / `--android-only`, `--yes` (skip the confirm), `--no-submit` (iOS: prepare but don't submit) / `--no-commit` (Android: prepare but don't commit), `--rollout=0.2` (Android staged rollout). Android promotion assumes the build is already on the Play internal track (from CI).

**Via GitHub Actions** (no local checkout needed, both platforms): Actions → **Promote** → *Run workflow*, then pick:
- `stage` — `external` (App Store + Play **production**) or `beta` (TestFlight "Beta Group" + Play **beta** track).
- `platform` — `both` (default), `ios`, or `android`.
- `notes` — release notes ("What to Test" for beta, required; "What's New" for external, blank uses a generic default).
- `rollout` — optional Android staged-rollout fraction (e.g. `0.2`); blank = 100%.
- `dry_run` — preview without changing anything.

It runs the same `promote.sh` the local flow does (iOS promotion is pure App Store Connect API calls, so it runs on an ubuntu runner).

### App Store Connect API key (`ios/secrets.env`)
`ios/secrets.env` (git-ignored) must export:
```
export TEAM_ID='...'                              # Apple Developer team id (e.g. 9N3SNHTGL7)
export APP_STORE_CONNECT_API_ISSUER_ID='...'      # Issuer ID (top of the API keys page)
export API_KEY_PATH='/path/to/AuthKey_XXXX.p8'    # the private key file you downloaded
export APP_STORE_CONNECT_API_KEY_ID='XXXX'        # optional — see note
```
Get these at App Store Connect → **Users and Access → Integrations → App Store Connect API**:
- The key **must have the Admin role** — a lesser role (e.g. App Manager) can upload builds but cannot create signing certificates, which makes the export fail.
- **Key ID:** the `.p8` does *not* contain its ID; Apple only encodes it in the download filename `AuthKey_<KEYID>.p8`. So if you keep that filename, `upload.sh` derives the ID automatically and you can omit `APP_STORE_CONNECT_API_KEY_ID`. If you rename the file, set `APP_STORE_CONNECT_API_KEY_ID` to the key's ID. (The `.p8` can only be downloaded once — keep it safe.)

### Troubleshooting
The script runs a fast auth precheck before building, so credential problems fail in seconds rather than after a full archive:
- **HTTP 401** — the key ID, issuer ID, and `.p8` don't all match. Confirm the Key ID matches the `.p8` (the `AuthKey_<ID>.p8` name) and the Issuer ID is the one on the API keys page.
- **HTTP 403** — the key authenticates but isn't Admin. Create an Admin key.
- **`exportArchive Signing certificate is invalid`** — a revoked/expired cert was selected. The script clears these automatically; if it recurs, a cert was revoked *during* the run, which almost always means signing was toggled in Xcode — don't do that, just run the script. (Apple auto-revokes the oldest distribution cert when you exceed the limit, so keep the number of distribution certs small in the portal.)

Try installing cocoapods with brew instead of gem: https://github.com/flutter/flutter/issues/157694.

## Screenshots
First, make sure you've implemented the fix in https://github.com/flutter/flutter/issues/91668 if the issue is still active. In short, make the following change to `~/homebrew/Caskroom/flutter/2.10.3/flutter/packages/integration_test/ios/Classes/IntegrationTestPlugin.m`:
```
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    [[IntegrationTestPlugin instance] setupChannels:registrar.messenger];
}
```

You may also need to `flutter clean` after this.

Then run this:
```
python3 screenshots/take_screenshots.py
```

This takes screenshots for both platforms on multiple devices. Upload them to both stores with:
```
python3 screenshots/upload_screenshots.py
```

This drives the App Store Connect and Google Play APIs directly (no fastlane) and supports `--ios-only`, `--android-only`, and `--dry-run`. The stores cap a listing at 10 (App Store) and 8 (Play) screenshots while the harness captures more than that, so the ordered selection lists at the top of the script choose which captures are published and in what order — edit them there to re-curate the storefronts.

Credentials:
- **App Store Connect:** the same `ios/secrets.env` that `ios/upload.sh` uses. Screenshots attach to an *editable* app version, so create the new version in App Store Connect first if one isn't already in Prepare for Submission.
- **Google Play:** a service account JSON key at `android/play_service_account.json` (git-ignored), or set `PLAY_SERVICE_ACCOUNT_JSON_PATH`. Use a key for the same service account CI publishes builds with (the `ANDROID_SERVICE_ACCOUNT_JSON` secret); it needs permission to edit the store listing in the Play Console. All Play changes happen inside a single edit that is committed only at the end, so a failed run changes nothing.

## General dev guide

Install the git hooks once after cloning — the pre-commit hook checks formatting and bumps the build number:
```sh
git config core.hooksPath .githooks
```

### Formatting

All Dart is formatted with `dart format`. The pre-commit hook blocks unformatted commits, CI (`.github/workflows/ci.yaml` → the `format` job) runs `dart format --output=none --set-exit-if-changed lib test integration_test test_driver`, and `.zed/settings.json` keeps Zed's format-on-save in step. Format everything with `dart format lib test integration_test test_driver`.
