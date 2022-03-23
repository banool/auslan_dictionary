# Auslan Dictionary

## Deploying to Android
This is done automatically via Github Actions.

## Deploying to iOS
Currently this must be done manually:
```
flutter pub get
flutter pub run flutter_launcher_icons:main
flutter pub run flutter_native_splash:create
flutter build ios --release --no-codesign
cd ios && ./publish_do_not_check_in.sh
```

If you run into problems with this, run some combination of these commands:
```
brew reinstall fastlane
rm Gemfile.lock
sudo gem cleanup
sudo gem update
pod install
```

To generate and upload screenshots:
```
fastlane screenshots
```
This invokes the `screenshots` lane we defined in the Fastfile.

## General dev guide

Run this before committing:
```
./bump_version.sh
```
Update: Now there is a hook that does this, you don't need to do it manually.


