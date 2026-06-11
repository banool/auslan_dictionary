#!/usr/bin/env bash
# Drive the multi-device e2e suite: two devices, four phases, one worker.
#
#   Phase A (device A): owner shares a list, mints an editor invite.
#   Phase B (device B): editor accepts the invite, adds a word.
#   Phase C (device A): owner re-signs-in on a fresh install (the test
#                       runner reinstalls per run), recovers the list,
#                       sees the edit, renames the list.
#   Phase D (device B): editor likewise recovers without the consumed
#                       invite and sees the rename; full convergence.
#
# Prereqs:
#   - A local worker:  cd dictionarylib/lists/workers && bunx wrangler dev --env dev
#   - Two booted devices (iOS simulators and/or Android emulators).
#
# Usage:
#   run.sh                       # picks the first two booted devices
#   run.sh <deviceA> <deviceB>   # explicit flutter device ids
#   run.sh --fresh ...           # uninstall the app from both first
#
# Android emulators are handled automatically: they reach the host's
# worker via 10.0.2.2 instead of localhost.

set -euo pipefail

FLUTTER=${FLUTTER:-/Users/dport/.development/flutter/bin/flutter}
API_BASE=${MD_API_BASE_URL:-http://localhost:8787}
TEST_AUTH_TOKEN=${MD_TEST_AUTH_TOKEN:-dev-integration-test-token-please-override}
APP_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUNDLE_ID=com.banool.auslanDictionary
ANDROID_PKG=com.banool.auslan_dictionary

cd "$APP_DIR"

FRESH=0
if [[ "${1:-}" == "--fresh" ]]; then FRESH=1; shift; fi

# --- Worker health -----------------------------------------------------------
if ! curl -fsS -m 5 "$API_BASE/v1/health" >/dev/null 2>&1; then
  echo "error: no worker at $API_BASE. Start one with:" >&2
  echo "  cd ../dictionarylib/lists/workers && bunx wrangler dev --env dev" >&2
  exit 1
fi

# --- Pick devices ------------------------------------------------------------
if [[ $# -ge 2 ]]; then
  DEVICE_A=$1; DEVICE_B=$2
else
  # Booted iOS simulators first, then running Android emulators.
  # (Portable across the macOS default bash 3.2 — no mapfile there.)
  DEVICES=()
  while IFS= read -r line; do DEVICES+=("$line"); done < <(
    { xcrun simctl list devices booted 2>/dev/null \
        | grep -Eo '[0-9A-F-]{36}' || true;
      adb devices 2>/dev/null | awk '/^emulator-/{print $1}' || true; } | head -2
  )
  if [[ ${#DEVICES[@]} -lt 2 ]]; then
    echo "error: need two booted devices (have ${#DEVICES[@]})." >&2
    echo "Boot two iOS simulators (xcrun simctl boot <udid>) and/or" >&2
    echo "Android emulators, or pass explicit device ids." >&2
    exit 1
  fi
  DEVICE_A=${DEVICES[0]}; DEVICE_B=${DEVICES[1]}
fi

# Android emulators reach the host loopback via 10.0.2.2.
base_url_for() {
  case "$1" in
    emulator-*) echo "${API_BASE/localhost/10.0.2.2}" ;;
    *)          echo "$API_BASE" ;;
  esac
}

RUN_ID=$(date +%s)
LOG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/md-e2e.XXXXXX")
echo "== multi-device e2e =="
echo "   device A: $DEVICE_A"
echo "   device B: $DEVICE_B"
echo "   worker:   $API_BASE"
echo "   run id:   $RUN_ID"
echo "   logs:     $LOG_DIR"

if [[ $FRESH -eq 1 ]]; then
  echo "-- removing existing installs (--fresh)"
  for D in "$DEVICE_A" "$DEVICE_B"; do
    case "$D" in
      emulator-*) adb -s "$D" uninstall "$ANDROID_PKG" >/dev/null 2>&1 || true ;;
      *)          xcrun simctl uninstall "$D" "$BUNDLE_ID" >/dev/null 2>&1 || true ;;
    esac
  done
fi

# --- Server-side cleanup of test users from previous runs --------------------
curl -fsS -m 10 -X POST "$API_BASE/v1/test/wipe" \
  -H "x-app-id: auslan" -H "x-test-auth-token: $TEST_AUTH_TOKEN" \
  >/dev/null || echo "warning: test wipe failed (continuing — run ids are fresh anyway)"

# --- Phase runner -------------------------------------------------------------
# run_phase <name> <device> <test-file> [extra --dart-define args...]
run_phase() {
  local name=$1 device=$2 file=$3; shift 3
  local log="$LOG_DIR/$name.log"
  echo "-- $name on $device"
  if ! "$FLUTTER" test "integration_test/multi_device/$file" -d "$device" \
      --dart-define=MD_RUN_ID="$RUN_ID" \
      --dart-define=MD_API_BASE_URL="$(base_url_for "$device")" \
      --dart-define=MD_TEST_AUTH_TOKEN="$TEST_AUTH_TOKEN" \
      "$@" 2>&1 | tee "$log"; then
    echo "FAIL: $name (log: $log)" >&2
    exit 1
  fi
}

scrape() { # scrape <log-name> <key>
  sed -n "s/^.*MD_OUT $2=//p" "$LOG_DIR/$1.log" | tail -1
}

run_phase phase-a "$DEVICE_A" phase_a_owner_shares_test.dart
LIST_ID=$(scrape phase-a LIST_ID)
INVITE_URL=$(scrape phase-a INVITE_URL)
[[ -n "$LIST_ID" && -n "$INVITE_URL" ]] || { echo "FAIL: phase A emitted no invite" >&2; exit 1; }

run_phase phase-b "$DEVICE_B" phase_b_editor_joins_test.dart \
  --dart-define=MD_INVITE_URL="$INVITE_URL"
EDITOR_KEY=$(scrape phase-b EDITOR_ADDED_KEY)
[[ -n "$EDITOR_KEY" ]] || { echo "FAIL: phase B emitted no editor key" >&2; exit 1; }

run_phase phase-c "$DEVICE_A" phase_c_owner_converges_test.dart \
  --dart-define=MD_LIST_ID="$LIST_ID" --dart-define=MD_EDITOR_KEY="$EDITOR_KEY"

run_phase phase-d "$DEVICE_B" phase_d_editor_converges_test.dart \
  --dart-define=MD_LIST_ID="$LIST_ID" --dart-define=MD_EDITOR_KEY="$EDITOR_KEY"

echo "== multi-device e2e: ALL FOUR PHASES PASSED =="
