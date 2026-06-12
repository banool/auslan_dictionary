# Auslan Dictionary

This repo contains all the code for Auslan Dictionary, the free forever video dictionary and revision tool for Australian sign language.

As of 2025-01-05 the app has been downloaded 372,975 times:
- Apple: 351k (based on First-Time Downloads)
  - Desktop / Laptop: 71%
  - iPhone: 26%
  - iPad: 3%
- Android: 21.8k

Note that 67% of downloads on Apple are [institutional](https://apple.stackexchange.com/a/428958), likely implying use by educational institutions. Ignoring those, there have been 103k unique downloads.

## Deploying to Android
This is done automatically via Github Actions.

## Deploying to iOS
Currently this must be done manually. Make sure `ios/publish.env` is configured (see below), then run:
```
flutter pub get
flutter pub run flutter_launcher_icons:main
flutter pub run flutter_native_splash:create
./ios/publish.sh
```

`ios/publish.sh` is fully hands-off: it verifies the API key, clears any revoked/expired certs and stale provisioning profiles, then builds with `xcodebuild` using **automatic** signing and uploads to TestFlight via `xcrun altool`. With an Admin API key, automatic signing creates and manages the distribution certificate and the App Store provisioning profile (including the Sign In with Apple + Associated Domains entitlements) — no fastlane, match, Xcode GUI, or manual cert management.

### App Store Connect API key (`ios/publish.env`)
`ios/publish.env` (git-ignored) must export:
```
export TEAM_ID='...'                              # Apple Developer team id (e.g. 9N3SNHTGL7)
export APP_STORE_CONNECT_API_ISSUER_ID='...'      # Issuer ID (top of the API keys page)
export API_KEY_PATH='/path/to/AuthKey_XXXX.p8'    # the private key file you downloaded
export APP_STORE_CONNECT_API_KEY_ID='XXXX'        # optional — see note
```
Get these at App Store Connect → **Users and Access → Integrations → App Store Connect API**:
- The key **must have the Admin role** — a lesser role (e.g. App Manager) can upload builds but cannot create signing certificates, which makes the export fail.
- **Key ID:** the `.p8` does *not* contain its ID; Apple only encodes it in the download filename `AuthKey_<KEYID>.p8`. So if you keep that filename, `publish.sh` derives the ID automatically and you can omit `APP_STORE_CONNECT_API_KEY_ID`. If you rename the file, set `APP_STORE_CONNECT_API_KEY_ID` to the key's ID. (The `.p8` can only be downloaded once — keep it safe.)

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
- **App Store Connect:** the same `ios/publish.env` that `ios/publish.sh` uses. Screenshots attach to an *editable* app version, so create the new version in App Store Connect first if one isn't already in Prepare for Submission.
- **Google Play:** a service account JSON key at `android/play_service_account.json` (git-ignored), or set `PLAY_SERVICE_ACCOUNT_JSON_PATH`. Use a key for the same service account CI publishes builds with (the `ANDROID_SERVICE_ACCOUNT_JSON` secret); it needs permission to edit the store listing in the Play Console. All Play changes happen inside a single edit that is committed only at the end, so a failed run changes nothing.

## General dev guide
When first pulling this repo, add this to `.git/hooks/pre-commit`:
```
#!/bin/bash

./bump_version.sh
git add pubspec.yaml
```
