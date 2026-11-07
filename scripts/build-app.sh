#!/bin/bash
# Builds DictateLocal.app into dist/.
#
# Environment:
#   VERSION             marketing version, default from the latest git tag
#   BUILD_NUMBER        bundle version, default the number of commits
#   CODESIGN_IDENTITY   signing identity; without it a local "DictateLocal Development"
#                       certificate is used if present, otherwise the app is signed ad hoc

set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh

APP_NAME="DictateLocal"
BUNDLE_ID="com.luismerk.DictateLocal"
APP_DIR="dist/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ENTITLEMENTS_FILE="Resources/DictateLocal.entitlements"

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

# The native build system skips MLX's Metal sources, which only Xcode's Metal toolchain could compile.
# MLX 0.32.2 is what mlx-swift-lm 3.32.3 builds, and its PyPI wheel carries the compiled shaders.
METALLIB_WHEEL_URL="https://files.pythonhosted.org/packages/py3/m/mlx-metal/mlx_metal-0.32.2-py3-none-macosx_26_0_arm64.whl"
METALLIB_WHEEL_SHA="e6abeac9ac526583"
METALLIB=".build/mlx-0.32.2.metallib"
if [ ! -f "${METALLIB}" ]; then
    echo "Fetching MLX shaders..."
    mkdir -p .build
    WHEEL=".build/mlx-metal.whl"
    curl -fsSL "${METALLIB_WHEEL_URL}" -o "${WHEEL}"
    [ "$(shasum -a 256 "${WHEEL}" | cut -c1-16)" = "${METALLIB_WHEEL_SHA}" ] || { echo "MLX shader wheel failed its checksum"; exit 1; }
    unzip -p "${WHEEL}" mlx/lib/mlx.metallib > "${METALLIB}"
    rm -f "${WHEEL}"
fi

echo "Compiling ${APP_NAME} ${VERSION} (${BUILD_NUMBER})..."
swift build -c release --build-system native --product "${APP_NAME}"
BIN_DIR=$(swift build -c release --build-system native --show-bin-path)

rm -rf "${APP_DIR}"
mkdir -p "${CONTENTS_DIR}/MacOS" "${RESOURCES_DIR}"
cp "${BIN_DIR}/${APP_NAME}" "${CONTENTS_DIR}/MacOS/"
# MLX looks for its shaders next to the binary.
cp "${METALLIB}" "${CONTENTS_DIR}/MacOS/mlx.metallib"

# SwiftPM resource bundles, for example from FluidAudio.
find "${BIN_DIR}" -maxdepth 1 -name "*.bundle" -exec cp -R {} "${RESOURCES_DIR}/" \;

echo "Generating AppIcon.icns..."
ICONSET=".build/AppIcon.iconset"
rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"
for size in 16 32 128 256 512; do
    sips -s format png -z "${size}" "${size}" Resources/AppIcon.png --out "${ICONSET}/icon_${size}x${size}.png" > /dev/null
    double=$((size * 2))
    sips -s format png -z "${double}" "${double}" Resources/AppIcon.png --out "${ICONSET}/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "${ICONSET}" -o "${RESOURCES_DIR}/AppIcon.icns"

cat <<PLIST > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>DictateLocal records your voice to turn it into text on this Mac.</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>DictateLocal types the recognized text into the app you are using.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Some SwiftPM resources are copied read-only, which blocks clearing their attributes.
chmod -R u+w "${APP_DIR}"
xattr -cr "${APP_DIR}"

# A certificate, even a self-signed one, keeps the app's identity stable across builds,
# so macOS keeps its Accessibility, Input Monitoring and Microphone permissions.
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "${SIGN_IDENTITY}" ]; then
    SIGN_IDENTITY=$(security find-identity -p codesigning 2>/dev/null | awk '/"DictateLocal Development"/ { print $2; exit }')
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
echo "Signing with: ${SIGN_IDENTITY}"
codesign --force --deep --options runtime --entitlements "${ENTITLEMENTS_FILE}" --sign "${SIGN_IDENTITY}" "${APP_DIR}"

echo "Built $(pwd)/${APP_DIR}"
