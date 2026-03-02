#!/bin/bash
#
# Build and upload the iOS app to TestFlight using xcodebuild and the
# App Store Connect API key. Uses automatic signing with cloud-managed
# certificates so no manual cert/profile management is needed.

set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR/.."

. ./ios/publish.env

[[ -z "${TEAM_ID:-}" ]] && echo 'Please set TEAM_ID' && exit 1
[[ -z "${APP_STORE_CONNECT_API_KEY_ID:-}" ]] && echo 'Please set APP_STORE_CONNECT_API_KEY_ID' && exit 1
[[ -z "${APP_STORE_CONNECT_API_ISSUER_ID:-}" ]] && echo 'Please set APP_STORE_CONNECT_API_ISSUER_ID' && exit 1
[[ -z "${API_KEY_PATH:-}" ]] && echo 'Please set API_KEY_PATH' && exit 1
[[ ! -f "$API_KEY_PATH" ]] && echo "API key not found at $API_KEY_PATH" && exit 1

ARCHIVE_PATH="build/ios/Runner.xcarchive"
EXPORT_PATH="build/ios/ipa"

echo "==> Cleaning build artifacts..."
flutter clean
flutter pub get

echo "==> Building Flutter app..."
flutter build ios --release --no-codesign

echo "==> Archiving with automatic signing..."
xcodebuild archive \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$API_KEY_PATH" \
  -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_API_ISSUER_ID"

echo "==> Exporting IPA..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist ios/ExportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$API_KEY_PATH" \
  -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_API_ISSUER_ID"

# https://github.com/flutter/flutter/issues/166367
echo "==> Stripping ._Symbols from IPA if present..."
IPA_FILE=$(ls "$EXPORT_PATH"/*.ipa 2>/dev/null | head -1)
if [[ -n "$IPA_FILE" ]]; then
  unzip -l "$IPA_FILE" | grep ._Symbols || true
  zip -d "$IPA_FILE" "._Symbols/" || true
fi

echo "==> Uploading to TestFlight..."
# altool expects AuthKey_<ID>.p8 in a private_keys directory.
PRIVATE_KEYS_DIR="$(pwd)/private_keys"
mkdir -p "$PRIVATE_KEYS_DIR"
ln -sf "$(cd "$(dirname "$API_KEY_PATH")" && pwd)/$(basename "$API_KEY_PATH")" \
  "$PRIVATE_KEYS_DIR/AuthKey_${APP_STORE_CONNECT_API_KEY_ID}.p8"
xcrun altool --upload-app \
  -f "$EXPORT_PATH"/*.ipa \
  -t ios \
  --apiKey "$APP_STORE_CONNECT_API_KEY_ID" \
  --apiIssuer "$APP_STORE_CONNECT_API_ISSUER_ID"
rm -rf "$PRIVATE_KEYS_DIR"

echo "==> Done! Build uploaded to TestFlight."
