#!/usr/bin/env bash
# Thin wrapper: the canonical multi-device e2e driver lives in the
# dictionarylib repo (scripts/multi_device_run.sh); this sets Auslan's
# app-specific values and hands over. Expects dictionarylib checked out as a
# sibling of this repo, or set DICTIONARYLIB_DIR.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
export MD_APP_DIR="$(cd "$HERE/../.." && pwd)"
export MD_BUNDLE_ID=com.banool.auslanDictionary
export MD_ANDROID_PKG=com.banool.auslan_dictionary
export MD_APP_ID=auslan

CANON="${DICTIONARYLIB_DIR:-$MD_APP_DIR/../dictionarylib}/scripts/multi_device_run.sh"
if [[ ! -f "$CANON" ]]; then
  echo "error: dictionarylib checkout not found ($CANON)." >&2
  echo "Clone https://github.com/banool/dictionarylib next to this repo, or set DICTIONARYLIB_DIR." >&2
  exit 1
fi
exec "$CANON" "$@"
