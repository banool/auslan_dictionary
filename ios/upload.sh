#!/bin/bash
# Build and upload the iOS app to TestFlight as an internal build. Thin wrapper:
# the canonical implementation lives in the dictionarylib repo
# (scripts/ios_upload.sh); this sets Auslan's app-specific values and hands over.
# Expects dictionarylib checked out as a sibling of this repo, or set
# DICTIONARYLIB_DIR.
#
# This only uploads. To release a build to beta testers or the public, use
# ./promote.sh (see its --stage flag).
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
export UPLOAD_APP_DIR="$(cd "$DIR/.." && pwd)"
export UPLOAD_BUNDLE_ID=com.banool.auslanDictionary

CANON="${DICTIONARYLIB_DIR:-$UPLOAD_APP_DIR/../dictionarylib}/scripts/ios_upload.sh"
if [[ ! -f "$CANON" ]]; then
  echo "error: dictionarylib checkout not found ($CANON)." >&2
  echo "Clone https://github.com/banool/dictionarylib next to this repo, or set DICTIONARYLIB_DIR." >&2
  exit 1
fi
exec "$CANON" "$@"
