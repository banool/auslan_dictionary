#!/bin/bash
# Build and upload the Android app to the Play internal track. Thin wrapper:
# the canonical implementation lives in the appci repo
# (scripts/android_upload.sh); this sets Auslan's app-specific values and hands
# over. Expects appci checked out as a sibling of this repo, or set APPCI_DIR.
#
# This only uploads (CI does the same automatically on app-change pushes). To
# release a build to beta testers or the public, use ./promote.sh (see its
# --stage flag).
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
export UPLOAD_APP_DIR="$(cd "$DIR/.." && pwd)"
export PLAY_PACKAGE_NAME=com.banool.auslan_dictionary
export PLAY_SERVICE_ACCOUNT_JSON_PATH="${PLAY_SERVICE_ACCOUNT_JSON_PATH:-$HOME/creds/play_auslan.json}"

CANON="${APPCI_DIR:-$UPLOAD_APP_DIR/../appci}/scripts/android_upload.sh"
if [[ ! -f "$CANON" ]]; then
  echo "error: appci checkout not found ($CANON)." >&2
  echo "Clone https://github.com/banool/appci next to this repo, or set APPCI_DIR." >&2
  exit 1
fi
exec "$CANON" "$@"
