#!/bin/bash
# Zips the signed app for a release and writes its SHA-256 next to it.

set -euo pipefail
cd "$(dirname "$0")/../.."
: "${VERSION:?set VERSION}"

APP="dist/DictateLocal.app"
codesign --verify --deep --strict "${APP}"
codesign -dr - "${APP}" 2>&1 | grep -q 'certificate leaf' || { echo "The app is not signed with a certificate"; exit 1; }

ZIP="dist/DictateLocal-${VERSION}.zip"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP}"
(cd dist && shasum -a 256 "$(basename "${ZIP}")" > "$(basename "${ZIP}").sha256")
cat "${ZIP}.sha256"
