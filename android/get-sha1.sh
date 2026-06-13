#!/usr/bin/env bash
#
# Print EVERY signing-certificate fingerprint form an app provider needs, for
# the debug or release(=upload) keystore, in one run:
#   SHA-1   (colon hex) -> Google OAuth Android client + Facebook Android.
#   SHA-256 (colon hex) -> assetlinks.json.ts sha256CertFingerprints + Facebook.
#   MSAL hash (base64, raw)         -> AndroidManifest.xml android:path.
#   MSAL hash (base64, URL-encoded) -> msauth:// redirect URI (main.dart + Azure).
# (The third keystore — the Play App Signing key — isn't in any local keystore;
# get it from the Play Console, see MANUAL_SETUP.md → "Android signing
# fingerprints" in the private backend repo.)
#
# Usage:
#   ./get-sha1.sh --env debug
#   ./get-sha1.sh --env release
#
# The release password / alias / keystore path are read from
# android/key.properties so no secrets live in this script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "Usage: $0 --env <debug|release>" >&2
  exit 2
}

environment=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      environment="${2:-}"
      shift 2 || usage
      ;;
    --env=*)
      environment="${1#*=}"
      shift
      ;;
    -h | --help)
      usage
      ;;
    *)
      echo "error: unknown argument '$1'" >&2
      usage
      ;;
  esac
done

case "$environment" in
  debug)
    keystore="$HOME/.android/debug.keystore"
    alias="androiddebugkey"
    storepass="android"
    keypass="android"
    ;;
  release)
    props="$SCRIPT_DIR/key.properties"
    if [[ ! -f "$props" ]]; then
      echo "error: $props not found" >&2
      exit 1
    fi
    # Pull KEY=VALUE entries out of key.properties.
    get_prop() { grep -E "^$1=" "$props" | head -n1 | cut -d'=' -f2-; }
    alias="$(get_prop keyAlias)"
    storepass="$(get_prop storePassword)"
    keypass="$(get_prop keyPassword)"
    store_file="$(get_prop storeFile)"
    # storeFile is relative to the app module (android/app), matching how
    # app/build.gradle's file() resolves it.
    if [[ "$store_file" = /* ]]; then
      keystore="$store_file"
    else
      keystore="$SCRIPT_DIR/app/$store_file"
    fi
    ;;
  *)
    usage
    ;;
esac

if [[ ! -f "$keystore" ]]; then
  echo "error: keystore not found: $keystore" >&2
  exit 1
fi

# Export the signing certificate once to a temp file, then derive every
# fingerprint form from it (DER bytes can't ride in a shell variable).
cert_der="$(mktemp)"
trap 'rm -f "$cert_der"' EXIT
if ! keytool -exportcert -alias "$alias" -keystore "$keystore" \
       -storepass "$storepass" -keypass "$keypass" >"$cert_der" 2>/dev/null \
   || [[ ! -s "$cert_der" ]]; then
  echo "error: failed to read certificate (wrong alias or password?)" >&2
  exit 1
fi

# Uppercase hex with a colon between every byte — the form keytool prints and
# that Google / Facebook / assetlinks expect.
colonize() { tr 'a-z' 'A-Z' | sed -E 's/(..)/\1:/g; s/:$//'; }

sha1_hex="$(openssl dgst -sha1 <"$cert_der" | sed 's/.*= *//' | colonize)"
sha256_hex="$(openssl dgst -sha256 <"$cert_der" | sed 's/.*= *//' | colonize)"
# MSAL wants the base64 of the *binary* SHA-1, not the hex.
b64="$(openssl dgst -sha1 -binary <"$cert_der" | openssl base64)"

# URL-encode the base64 for the redirect-URI form (main.dart / Azure). Only
# '+', '/' and '=' can appear in base64; encode '%' first for safety.
encoded="${b64//%/%25}"
encoded="${encoded//+/%2B}"
encoded="${encoded//\//%2F}"
encoded="${encoded//=/%3D}"

package="$(grep -E 'applicationId' "$SCRIPT_DIR/app/build.gradle" \
  | head -n1 | sed -E 's/.*"([^"]+)".*/\1/')"

echo "env:       $environment"
echo "keystore:  $keystore"
echo
echo "SHA-1   (colon hex): $sha1_hex"
echo "  -> Google OAuth Android client (one per keystore) + Facebook Android."
echo "SHA-256 (colon hex): $sha256_hex"
echo "  -> assetlinks.json.ts sha256CertFingerprints + Facebook Android."
echo
echo "MSAL hash (base64, raw):         $b64"
echo "  -> AndroidManifest.xml BrowserTabActivity  android:path=\"/$b64\""
if [[ -n "$package" ]]; then
  echo "MSAL hash (base64, URL-encoded): $encoded"
  echo "  -> main.dart microsoftAndroid*RedirectUri + Azure redirect URI:"
  echo "       msauth://$package/$encoded"
fi
