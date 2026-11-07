#!/bin/bash
# Packs the signed app into a drag-to-install disk image and writes its SHA-256 next to it.
#
# Environment:
#   VERSION             release version, for the file name
#   CODESIGN_IDENTITY   identity that also signs the disk image; ad hoc without it
#   DMGBUILD            dmgbuild executable, default `dmgbuild` from PATH

set -euo pipefail
cd "$(dirname "$0")/../.."
: "${VERSION:?set VERSION}"

APP="dist/DictateLocal.app"
codesign --verify --deep --strict "${APP}"
codesign -dr - "${APP}" 2>&1 | grep -q 'certificate leaf' || { echo "The app is not signed with a certificate"; exit 1; }

DMG="dist/DictateLocal-${VERSION}.dmg"
rm -f "${DMG}"
"${DMGBUILD:-dmgbuild}" -s Resources/dmg-settings.py -D app="${APP}" "DictateLocal" "${DMG}"
codesign --force --sign "${CODESIGN_IDENTITY:--}" "${DMG}"
hdiutil verify "${DMG}" >/dev/null

(cd dist && shasum -a 256 "$(basename "${DMG}")" > "$(basename "${DMG}").sha256")
cat "${DMG}.sha256"
