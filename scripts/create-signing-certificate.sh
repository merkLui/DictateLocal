#!/bin/bash
# Creates a self-signed code signing certificate.
#
#   scripts/create-signing-certificate.sh
#       adds "DictateLocal Development" to your login keychain; scripts/build-app.sh then uses it,
#       so macOS keeps the app's permissions across your own builds
#   scripts/create-signing-certificate.sh --export release.p12 "DictateLocal Release"
#       writes a password-protected .p12 for the release workflow instead (see docs/RELEASING.md)
#
# KEYCHAIN overrides the keychain to import into.

set -euo pipefail

EXPORT_PATH=""
if [ "${1:-}" = "--export" ]; then
    EXPORT_PATH="${2:?Usage: --export <file.p12> [name]}"
    shift 2
fi
NAME="${1:-DictateLocal Development}"
KEYCHAIN="${KEYCHAIN:-${HOME}/Library/Keychains/login.keychain-db}"

WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

cat > "${WORK}/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = ${NAME}
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
    -config "${WORK}/openssl.cnf" -keyout "${WORK}/key.pem" -out "${WORK}/cert.pem" 2>/dev/null

PASSWORD=$(/usr/bin/openssl rand -hex 16)
# LibreSSL's defaults are the legacy algorithms that `security import` understands.
/usr/bin/openssl pkcs12 -export -name "${NAME}" -inkey "${WORK}/key.pem" -in "${WORK}/cert.pem" \
    -out "${WORK}/cert.p12" -passout "pass:${PASSWORD}"

if [ -n "${EXPORT_PATH}" ]; then
    PASSWORD_PATH="${EXPORT_PATH%.p12}.password"
    (umask 077; cp "${WORK}/cert.p12" "${EXPORT_PATH}"; printf '%s' "${PASSWORD}" > "${PASSWORD_PATH}")
    echo "Wrote ${EXPORT_PATH} for \"${NAME}\" and its password to ${PASSWORD_PATH}."
    echo "Store both as repository secrets:"
    echo "  base64 -i ${EXPORT_PATH} | gh secret set SIGNING_CERTIFICATE_P12"
    echo "  gh secret set SIGNING_CERTIFICATE_PASSWORD < ${PASSWORD_PATH}"
    echo "Keep a copy of both in a password manager: a new certificate makes users grant permissions again."
    exit 0
fi

security import "${WORK}/cert.p12" -k "${KEYCHAIN}" -P "${PASSWORD}" -T /usr/bin/codesign >/dev/null
echo "Added \"${NAME}\" to ${KEYCHAIN}. scripts/build-app.sh will sign with it."
