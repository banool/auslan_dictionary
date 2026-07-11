#!/bin/bash
# Build and upload the iOS app to TestFlight. Thin wrapper: the canonical
# implementation lives in the dictionarylib repo (scripts/ios_publish.sh);
# this sets Auslan's app-specific values and hands over. Expects dictionarylib
# checked out as a sibling of this repo, or set DICTIONARYLIB_DIR.
#
# Pass --beta to also promote the uploaded build to the external tester group.
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
export PUBLISH_APP_DIR="$(cd "$DIR/.." && pwd)"
export PUBLISH_BUNDLE_ID=com.banool.auslanDictionary
export PUBLISH_BETA_GROUP="Beta Group"

CANON="${DICTIONARYLIB_DIR:-$PUBLISH_APP_DIR/../dictionarylib}/scripts/ios_publish.sh"
if [[ ! -f "$CANON" ]]; then
  echo "error: dictionarylib checkout not found ($CANON)." >&2
  echo "Clone https://github.com/banool/dictionarylib next to this repo, or set DICTIONARYLIB_DIR." >&2
  exit 1
fi
exec "$CANON" "$@"
