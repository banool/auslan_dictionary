#!/bin/bash
#
# Build and upload the iOS app to TestFlight using xcodebuild and the
# App Store Connect API key.
#
# Fully hands-off. Signing is AUTOMATIC: with an Admin App Store Connect API key,
# xcodebuild's -allowProvisioningUpdates creates and manages the distribution
# certificate AND the App Store provisioning profile (including the app's Sign In
# with Apple + Associated Domains entitlements) with no Xcode GUI or portal
# steps. Credentials come from ios/publish.env. See README.md ->
# "Deploying to iOS" for setup and troubleshooting.
#
# Pass --beta to also promote the uploaded build to the external tester group
# ("Beta Group") after upload — it prompts for "What to Test" notes up front.

set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR/.."

. ./ios/publish.env

[[ -z "${TEAM_ID:-}" ]] && echo 'Please set TEAM_ID' && exit 1
[[ -z "${APP_STORE_CONNECT_API_ISSUER_ID:-}" ]] && echo 'Please set APP_STORE_CONNECT_API_ISSUER_ID' && exit 1
[[ -z "${API_KEY_PATH:-}" ]] && echo 'Please set API_KEY_PATH' && exit 1
[[ ! -f "$API_KEY_PATH" ]] && echo "API key not found at $API_KEY_PATH" && exit 1

# The key ID is NOT stored inside the .p8 — Apple only encodes it in the
# download filename "AuthKey_<ID>.p8". Derive it from that filename when the key
# keeps Apple's name, otherwise fall back to APP_STORE_CONNECT_API_KEY_ID from
# publish.env. (So you can drop that env var entirely by keeping the key named
# AuthKey_<ID>.p8.)
KEY_ID="${APP_STORE_CONNECT_API_KEY_ID:-}"
_kf="$(basename "$API_KEY_PATH")"
if [[ "$_kf" == AuthKey_*.p8 ]]; then
  _kf="${_kf#AuthKey_}"
  KEY_ID="${_kf%.p8}"
fi
if [[ -z "$KEY_ID" ]]; then
  echo "Set APP_STORE_CONNECT_API_KEY_ID in ios/publish.env, or name the key file AuthKey_<ID>.p8" >&2
  exit 1
fi

# --beta: after uploading, also promote this build to the external tester group.
# The flag is parsed and the notes prompted up front so the prompt doesn't
# interrupt the long build/upload.
BETA=false
for arg in "$@"; do
  case "$arg" in
    --beta) BETA=true ;;
    *) echo "Unknown argument: $arg (only --beta is supported)" >&2; exit 1 ;;
  esac
done

BETA_GROUP="Beta Group"
BETA_NOTES=""
if [[ "$BETA" == true ]]; then
  echo "==> --beta: this build will be sent to the '$BETA_GROUP' external group after upload."
  echo "    External testing needs 'What to Test' notes. Type them now, then finish with"
  echo "    an empty line (or Ctrl-D):"
  while IFS= read -r line; do
    if [[ -z "$line" ]]; then
      break
    fi
    BETA_NOTES+="$line"$'\n'
  done
  BETA_NOTES="${BETA_NOTES%$'\n'}"
  if [[ -z "$BETA_NOTES" ]]; then
    echo "No 'What to Test' notes entered — aborting." >&2
    exit 1
  fi
  # The beta-promotion helper lives in the dictionarylib repo (sibling
  # checkout, or set DICTIONARYLIB_DIR). Resolve it up front so a missing
  # checkout fails fast here, not after the ~20-minute build/upload.
  APPSTORE_BETA="${DICTIONARYLIB_DIR:-../dictionarylib}/scripts/appstore_beta.py"
  if [[ ! -f "$APPSTORE_BETA" ]]; then
    echo "error: $APPSTORE_BETA not found. Clone dictionarylib next to this repo, or set DICTIONARYLIB_DIR." >&2
    exit 1
  fi
fi

ARCHIVE_PATH="build/ios/Runner.xcarchive"
EXPORT_PATH="build/ios/ipa"

# --- helpers ----------------------------------------------------------------

_b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# Print a short-lived ES256 JWT for the App Store Connect API, signed with the
# .p8. (xcodebuild/altool build their own internally; this is only so we can
# verify the credentials up front.)
_appstore_jwt() {
  local now exp h p si der parse r s
  now=$(date +%s)
  exp=$((now + 600))
  h=$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$KEY_ID" | _b64url)
  p=$(printf '{"iss":"%s","iat":%s,"exp":%s,"aud":"appstoreconnect-v1"}' \
    "$APP_STORE_CONNECT_API_ISSUER_ID" "$now" "$exp" | _b64url)
  si="$h.$p"
  der=$(mktemp)
  printf '%s' "$si" | openssl dgst -sha256 -sign "$API_KEY_PATH" -out "$der" 2>/dev/null
  parse=$(openssl asn1parse -inform DER -in "$der" 2>/dev/null)
  rm -f "$der"
  # ECDSA DER signature is SEQUENCE { INTEGER r, INTEGER s }; JOSE wants raw
  # 32-byte r || 32-byte s.
  r=$(echo "$parse" | grep INTEGER | sed -n '1p' | sed 's/.*://')
  s=$(echo "$parse" | grep INTEGER | sed -n '2p' | sed 's/.*://')
  _pad() { local x="$1"; while [ "${#x}" -lt 64 ]; do x="0$x"; done; printf '%s' "${x: -64}"; }
  printf '%s.%s' "$si" \
    "$(printf '%s%s' "$(_pad "$r")" "$(_pad "$s")" | xxd -r -p | _b64url)"
}

# Fail fast if the API key can't authenticate or lacks provisioning access, so
# we don't sit through a full archive only to hit a 401 at export.
auth_precheck() {
  echo "==> Verifying App Store Connect API key ($KEY_ID)..."
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer $(_appstore_jwt)" \
    'https://api.appstoreconnect.apple.com/v1/certificates?limit=1' 2>/dev/null || echo 000)
  case "$code" in
    200) echo "   OK — key authenticates and can manage certificates." ;;
    401)
      echo "ERROR: App Store Connect rejected the key (HTTP 401)." >&2
      echo "       The key ID, issuer ID, and .p8 don't all match." >&2
      echo "       Fix: README.md -> 'Deploying to iOS'." >&2
      exit 1
      ;;
    403)
      echo "ERROR: the key authenticated but can't manage certificates (HTTP 403)." >&2
      echo "       It needs the Admin role." >&2
      echo "       Fix: README.md -> 'Deploying to iOS'." >&2
      exit 1
      ;;
    000) echo "WARNING: couldn't reach App Store Connect to verify the key; continuing." >&2 ;;
    *) echo "WARNING: unexpected response verifying the key (HTTP $code); continuing." >&2 ;;
  esac
}

# Delete revoked/expired Apple code-signing certs from the keychain so automatic
# signing can't latch onto an invalid one. Only ever touches certs that are
# already revoked/expired AND whose name starts with an Apple signing prefix —
# never a valid cert or anything else. May prompt for the keychain password.
clean_invalid_certs() {
  local removed=0 sha1 cn f tmp

  # Revoked identities (find-identity annotates them with CSSMERR_TP_CERT_REVOKED).
  while IFS= read -r sha1; do
    [[ -n "$sha1" ]] || continue
    if security delete-identity -Z "$sha1" >/dev/null 2>&1 ||
      security delete-certificate -Z "$sha1" >/dev/null 2>&1; then
      echo "   removed revoked cert $sha1"
      removed=$((removed + 1))
    fi
  done < <(security find-identity -v -p codesigning 2>/dev/null |
    awk '/CSSMERR_TP_CERT_REVOKED/ {print $2}')

  # Expired signing certs (date already past).
  tmp="$(mktemp -d)"
  for cn in "Apple Distribution" "Apple Development" "iPhone Distribution" "iPhone Developer"; do
    security find-certificate -a -c "$cn" -p >"$tmp/dump.pem" 2>/dev/null || true
    [[ -s "$tmp/dump.pem" ]] || continue
    rm -f "$tmp"/c_*.pem
    awk -v d="$tmp" '/-----BEGIN CERTIFICATE-----/{n++} n>0{print > sprintf("%s/c_%03d.pem", d, n)}' "$tmp/dump.pem"
    for f in "$tmp"/c_*.pem; do
      [[ -f "$f" ]] || continue
      if ! openssl x509 -in "$f" -noout -checkend 0 >/dev/null 2>&1; then
        sha1=$(openssl x509 -in "$f" -noout -fingerprint -sha1 2>/dev/null | cut -d= -f2 | tr -d ':')
        if security delete-certificate -Z "$sha1" >/dev/null 2>&1 ||
          security delete-identity -Z "$sha1" >/dev/null 2>&1; then
          echo "   removed expired cert $sha1"
          removed=$((removed + 1))
        fi
      fi
    done
  done
  rm -rf "$tmp"

  if [[ "$removed" -eq 0 ]]; then
    echo "   no invalid certs found."
  fi
}

# Delete cached provisioning profiles whose embedded signing cert is no longer a
# valid identity in the keychain (revoked/expired/missing). A stale profile — a
# leftover fastlane "match" profile pointing at a revoked cert, say — makes the
# automatic export fail with "Profile failed qualification checks". Removing it
# lets automatic signing regenerate a fresh, qualifying profile.
clean_invalid_profiles() {
  local pp="$HOME/Library/MobileDevice/Provisioning Profiles"
  [[ -d "$pp" ]] || { echo "   no profiles directory."; return 0; }
  local valid removed=0 f pl name i b64 sha1 ok
  valid=$(security find-identity -v -p codesigning 2>/dev/null |
    grep -v CSSMERR | awk '{print toupper($2)}' || true)
  for f in "$pp"/*.mobileprovision; do
    [[ -f "$f" ]] || continue
    pl=$(security cms -D -i "$f" 2>/dev/null) || continue
    name=$(printf '%s' "$pl" | plutil -extract Name raw - 2>/dev/null || echo '?')
    ok=no
    i=0
    while [[ "$i" -lt 100 ]]; do
      b64=$(printf '%s' "$pl" | plutil -extract "DeveloperCertificates.$i" raw - 2>/dev/null || true)
      [[ -n "$b64" ]] || break
      sha1=$(printf '%s' "$b64" | base64 -D 2>/dev/null |
        openssl x509 -inform der -noout -fingerprint -sha1 2>/dev/null |
        cut -d= -f2 | tr -d ':' || true)
      if [[ -n "$sha1" ]] && printf '%s\n' "$valid" | grep -qi "$sha1"; then
        ok=yes
        break
      fi
      i=$((i + 1))
    done
    if [[ "$ok" == "no" ]]; then
      if rm -f "$f"; then
        echo "   removed stale profile: $name"
        removed=$((removed + 1))
      fi
    fi
  done
  if [[ "$removed" -eq 0 ]]; then
    echo "   no stale profiles found."
  fi
}

# --- run --------------------------------------------------------------------

auth_precheck

if [[ "${SKIP_CERT_CLEANUP:-0}" != "1" ]]; then
  echo "==> Removing any revoked/expired signing certificates..."
  clean_invalid_certs
  echo "==> Removing any stale provisioning profiles..."
  clean_invalid_profiles
fi

# Informational only. With an Admin API key, a missing distribution cert is fine:
# -allowProvisioningUpdates creates one during archiving. The `|| true` keeps
# `pipefail` from aborting when grep finds zero matches.
valid_dist=$(security find-identity -v -p codesigning 2>/dev/null |
  grep "Apple Distribution" | grep -vc CSSMERR || true)
echo "==> $valid_dist valid distribution identity(ies) in the keychain."
if [[ "${valid_dist:-0}" -lt 1 ]]; then
  echo "    None yet — the Admin API key will create one during signing."
fi

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
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_API_ISSUER_ID"

echo "==> Exporting IPA..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist ios/ExportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$API_KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
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
  "$PRIVATE_KEYS_DIR/AuthKey_${KEY_ID}.p8"
xcrun altool --upload-app \
  -f "$EXPORT_PATH"/*.ipa \
  -t ios \
  --apiKey "$KEY_ID" \
  --apiIssuer "$APP_STORE_CONNECT_API_ISSUER_ID"
rm -rf "$PRIVATE_KEYS_DIR"

if [[ "$BETA" == true ]]; then
  echo "==> Promoting the build to the '$BETA_GROUP' external group..."
  # The build number is the +N part of the pubspec version; it identifies the
  # build in App Store Connect.
  BUILD_NUMBER=$(grep -E '^version:' pubspec.yaml | sed -E 's/.*\+([0-9]+).*$/\1/')
  ASC_BUNDLE_ID="com.banool.auslanDictionary" \
  ASC_BUILD_NUMBER="$BUILD_NUMBER" \
  ASC_GROUP_NAME="$BETA_GROUP" \
  ASC_WHATS_NEW="$BETA_NOTES" \
  APP_STORE_CONNECT_API_KEY_ID="$KEY_ID" \
  APP_STORE_CONNECT_API_ISSUER_ID="$APP_STORE_CONNECT_API_ISSUER_ID" \
  API_KEY_PATH="$API_KEY_PATH" \
  python3 "$APPSTORE_BETA"
fi

echo "==> Done! Build uploaded to TestFlight."

# ---------------------------------------------------------------------------
# Troubleshooting (see README.md -> "Deploying to iOS")
# ---------------------------------------------------------------------------
# - "App Store Connect API key (HTTP 401)" from the precheck: the key ID, issuer,
#   and .p8 don't match. The key ID is the AuthKey_<ID>.p8 filename Apple gave
#   you; the issuer is on the App Store Connect API keys page.
# - "HTTP 403" from the precheck: the key isn't Admin; create an Admin key.
# - "Signing certificate is invalid": handled by the up-front cleanup. If it
#   recurs, a cert was revoked mid-run — don't toggle signing in Xcode.
