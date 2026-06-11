#!/usr/bin/env bash
#
# Print the MSAL Android signature hash (base64-encoded SHA-1 of the signing
# certificate) for the debug or release keystore, plus the matching
# `msauth://` redirect URI. Register the hash in the Azure app registration
# (Authentication -> Add a platform -> Android) and paste the redirect URI
# into `microsoftAndroidRedirectUri` in the app's main.dart. See
# dictionarylib/lists/MANUAL_SETUP.md section 4.
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

hash="$(keytool -exportcert -alias "$alias" -keystore "$keystore" \
  -storepass "$storepass" -keypass "$keypass" 2>/dev/null \
  | openssl sha1 -binary | openssl base64)"

if [[ -z "$hash" ]]; then
  echo "error: failed to compute signature hash (wrong alias or password?)" >&2
  exit 1
fi

# URL-encode the base64 for use in the redirect URI / manifest path. Only
# '+', '/' and '=' can appear in base64; encode '%' first for safety.
encoded="${hash//%/%25}"
encoded="${encoded//+/%2B}"
encoded="${encoded//\//%2F}"
encoded="${encoded//=/%3D}"

package="$(grep -E 'applicationId' "$SCRIPT_DIR/app/build.gradle" \
  | head -n1 | sed -E 's/.*"([^"]+)".*/\1/')"

echo "env:            $environment"
echo "keystore:       $keystore"
echo "signature hash: $hash"
if [[ -n "$package" ]]; then
  echo "redirect URI:   msauth://$package/$encoded"
fi
