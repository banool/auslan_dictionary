#!/bin/bash
# Promote Auslan's already-uploaded beta builds to full store releases (App Store
# + Google Play). Thin wrapper: the canonical implementation lives in the
# dictionarylib repo (scripts/release.sh); this sets Auslan's app-specific values
# and hands over. Expects dictionarylib checked out as a sibling of this repo, or
# set DICTIONARYLIB_DIR. Run `./release.sh --dry-run` first to see the plan.
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
export RELEASE_APP_DIR="$DIR"
export RELEASE_BUNDLE_ID=com.banool.auslanDictionary
export RELEASE_PACKAGE_NAME=com.banool.auslan_dictionary

CANON="${DICTIONARYLIB_DIR:-$RELEASE_APP_DIR/../dictionarylib}/scripts/release.sh"
if [[ ! -f "$CANON" ]]; then
  echo "error: dictionarylib checkout not found ($CANON)." >&2
  echo "Clone https://github.com/banool/dictionarylib next to this repo, or set DICTIONARYLIB_DIR." >&2
  exit 1
fi
exec "$CANON" "$@"
