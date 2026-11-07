#!/bin/bash
# Imports the release certificate from repository secrets into a temporary keychain.

set -euo pipefail
: "${SIGNING_CERTIFICATE_P12:?missing secret SIGNING_CERTIFICATE_P12}"
: "${SIGNING_CERTIFICATE_PASSWORD:?missing secret SIGNING_CERTIFICATE_PASSWORD}"

KEYCHAIN="${RUNNER_TEMP}/signing.keychain-db"
KEYCHAIN_PASSWORD=$(openssl rand -hex 16)
P12="${RUNNER_TEMP}/signing.p12"

echo "${SIGNING_CERTIFICATE_P12}" | base64 --decode > "${P12}"
security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}"
security set-keychain-settings -lut 3600 "${KEYCHAIN}"
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}"
security import "${P12}" -k "${KEYCHAIN}" -P "${SIGNING_CERTIFICATE_PASSWORD}" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}" >/dev/null
security list-keychains -d user -s "${KEYCHAIN}" $(security list-keychains -d user | tr -d '"')
rm -f "${P12}"
security find-identity -p codesigning "${KEYCHAIN}"
