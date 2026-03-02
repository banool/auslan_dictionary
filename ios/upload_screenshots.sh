#!/bin/bash
#
# Upload screenshots to App Store Connect using the App Store Connect API key.
# The Apple App Store will expect that you also upload a build for this app
# version first.

set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR/.."

. ./ios/publish.env

[[ -z "${APP_STORE_CONNECT_API_KEY_ID:-}" ]] && echo 'Please set APP_STORE_CONNECT_API_KEY_ID' && exit 1
[[ -z "${APP_STORE_CONNECT_API_ISSUER_ID:-}" ]] && echo 'Please set APP_STORE_CONNECT_API_ISSUER_ID' && exit 1
[[ -z "${API_KEY_PATH:-}" ]] && echo 'Please set API_KEY_PATH' && exit 1
[[ ! -f "$API_KEY_PATH" ]] && echo "API key not found at $API_KEY_PATH" && exit 1

echo "Screenshot upload to App Store Connect without fastlane is not yet"
echo "supported by this script. Use Transporter.app or the App Store Connect"
echo "web interface to upload screenshots manually."
echo ""
echo "Screenshots are located at: screenshots/ios/"
