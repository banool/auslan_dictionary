#!/usr/bin/env bash
# Thin wrapper: the canonical multi-device e2e driver lives in the
# appci repo (scripts/multi_device_run.sh); this sets Auslan's
# app-specific values and hands over. Expects appci checked out as a
# sibling of this repo, or set APPCI_DIR.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
export MD_APP_DIR="$(cd "$HERE/../.." && pwd)"
export MD_BUNDLE_ID=com.banool.auslanDictionary
export MD_ANDROID_PKG=com.banool.auslan_dictionary
export MD_APP_ID=auslan

CANON="${APPCI_DIR:-$MD_APP_DIR/../appci}/scripts/multi_device_run.sh"
if [[ ! -f "$CANON" ]]; then
  echo "error: appci checkout not found ($CANON)." >&2
  echo "Clone https://github.com/banool/appci next to this repo, or set APPCI_DIR." >&2
  exit 1
fi
exec "$CANON" "$@"
