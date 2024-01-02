# Auslan Dictionary

This repo contains all the code for Auslan Dictionary, the free forever video dictionary and revision tool for Australian sign language.

As of 2024-01-02 the app has been downloaded by 158k unique users:
- Apple: 136k (based on First-Time Downloads)
  - Desktop: 70k
  - iPhone: 59k
  - iPad: 7k
- Android: 22k

## Deploying to Android
This is done automatically via Github Actions.

## Deploying to iOS
Currently this must be done manually:
```
flutter pub get
flutter pub run flutter_launcher_icons:main
flutter pub run flutter_native_splash:create
flutter build ios --release --no-codesign
./ios/publish.sh
```

If you run into problems with this, run some combination of these commands:
```
brew reinstall fastlane
rm Gemfile.lock
sudo gem cleanup
sudo gem update
pod install
```

If you have issues with the cert stuff, try this:
```
. publish.env && yes | fastlane match nuke distribution && yes | fastlane match nuke development
```

Make sure you're using an up to date ruby / gem and it is configured first in your PATH. Make sure `pod` is coming from that gem install too. [See here](https://stackoverflow.com/questions/20755044/how-do-i-install-cocoapods). Make sure to use the one with `-n`.

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

See my [Stack OVverflow question](https://stackoverflow.com/questions/71699078/how-to-locate-elements-in-ios-ui-test-for-flutter-fastlane-screnshots/71801310#71801310) for more information about this whole setup.

## General dev guide
When first pulling this repo, add this to `.git/hooks/pre-commit`:
```
#!/bin/bash

./bump_version.sh
git add pubspec.yaml
```
