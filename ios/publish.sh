#!/bin/sh

cd "$(dirname "$0")"

. publish.env

[[ -z "${FASTLANE_USER}" ]] && echo 'Please set FASTLANE_USER' && exit
[[ -z "${FASTLANE_PASSWORD}" ]] && echo 'Please set FASTLANE_PASSWORD' && exit
[[ -z "${FASTLANE_SESSION}" ]] && echo 'Please set FASTLANE_SESSION' && exit
[[ -z "${FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD}" ]] && echo 'Please set FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD' && exit
[[ -z "${MATCH_KEYCHAIN_NAME}" ]] && echo 'Please set MATCH_KEYCHAIN_NAME' && exit
[[ -z "${MATCH_KEYCHAIN_PASSWORD}" ]] && echo 'Please set MATCH_KEYCHAIN_PASSWORD' && exit
[[ -z "${MATCH_PASSWORD}" ]] && echo 'Please set MATCH_PASSWORD' && exit

fastlane ios beta
