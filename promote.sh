#!/bin/bash
# Promote Auslan's already-uploaded build to a wider audience (App Store + Google
# Play). Thin wrapper: the canonical implementation lives in the dictionarylib
# repo (scripts/promote.sh); this sets Auslan's app-specific values and hands
# over. Expects dictionarylib checked out as a sibling of this repo, or set
# DICTIONARYLIB_DIR.
#
#   ./promote.sh --stage beta        # -> TestFlight "Beta Group" + Play beta track
#   ./promote.sh --stage external    # -> App Store + Play production
# Run with --dry-run first to see the plan.
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
export PROMOTE_APP_DIR="$DIR"
export PROMOTE_BUNDLE_ID=com.banool.auslanDictionary
export PROMOTE_PACKAGE_NAME=com.banool.auslan_dictionary
export PROMOTE_BETA_GROUP="Beta Group"

CANON="${DICTIONARYLIB_DIR:-$PROMOTE_APP_DIR/../dictionarylib}/scripts/promote.sh"
if [[ ! -f "$CANON" ]]; then
  echo "error: dictionarylib checkout not found ($CANON)." >&2
  echo "Clone https://github.com/banool/dictionarylib next to this repo, or set DICTIONARYLIB_DIR." >&2
  exit 1
fi
exec "$CANON" "$@"
