# Auslan Dictionary

## Deploying to Android
This is done automatically via Github Actions.

## Deploying to iOS
Currently this must be done manually:
```
flutter pub get
flutter pub run flutter_launcher_icons:main
flutter build ios --release --no-codesign
./publish_do_not_check_in.sh
```

## General dev guide

Run this before committing:
```
./bump_version.sh
```
Update: Now there is a hook that does this, you don't need to do it manually.
