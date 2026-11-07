# Sourced by the other scripts. With only the Command Line Tools installed, their newest
# SDK can lack the SwiftUI macro plugin, so the build falls back to the macOS 26.5 SDK.

COMMAND_LINE_TOOLS="/Library/Developer/CommandLineTools"
if [ "$(xcode-select -p 2>/dev/null)" = "${COMMAND_LINE_TOOLS}" ]; then
    SDK_265="${COMMAND_LINE_TOOLS}/SDKs/MacOSX26.5.sdk"
    if [ -z "${SDKROOT:-}" ] && [ -d "${SDK_265}" ]; then
        export SDKROOT="${SDK_265}"
    fi
fi
