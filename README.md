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
Currently this must be done manually. Make sure `ios/publish.env` is configured with your App Store Connect API key details, then run:
```
flutter pub get
flutter pub run flutter_launcher_icons:main
flutter pub run flutter_native_splash:create
./ios/publish.sh
```

The script uses `xcodebuild` with automatic signing and uploads to TestFlight via `xcrun altool`. No fastlane, match, or manual cert management needed.

Try installing cocoapods with brew instead of gem: https://github.com/flutter/flutter/issues/157694.

## Screenshots
First, make sure you've implemented the fix in https://github.com/flutter/flutter/issues/91668 if the issue is still active. In short, make the following change to `~/homebrew/Caskroom/flutter/2.10.3/flutter/packages/integration_test/ios/Classes/IntegrationTestPlugin.m`
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

This takes screenshots for both platforms on multiple devices. You can then upload them with these commands:
```
ios/upload_screenshots.sh
```
The Apple App Store will expect that you also upload a build for this app version first. You might need to also manually upload the photos for the 2nd gen 12.9 inch iPad (just use the 5th gen pics).

For Android, you need to just go to the Google Play Console and do it manually right now.

## General dev guide
When first pulling this repo, add this to `.git/hooks/pre-commit`:
```
#!/bin/bash

./bump_version.sh
git add pubspec.yaml
```
