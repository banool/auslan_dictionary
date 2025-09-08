#!/bin/sh

cd "$(dirname "$0")"

. publish.env

[[ -z "${FASTLANE_USER}" ]] && echo 'Please set FASTLANE_USER' && exit
[[ -z "${MATCH_KEYCHAIN_NAME}" ]] && echo 'Please set MATCH_KEYCHAIN_NAME' && exit
[[ -z "${MATCH_KEYCHAIN_PASSWORD}" ]] && echo 'Please set MATCH_KEYCHAIN_PASSWORD' && exit
[[ -z "${MATCH_PASSWORD}" ]] && echo 'Please set MATCH_PASSWORD' && exit

fastlane ios beta
