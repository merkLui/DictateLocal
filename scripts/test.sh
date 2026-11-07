#!/bin/bash
# Runs the unit tests. Extra arguments go to `swift test`, for example `--filter Shortcut`.

set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh

ARGS=(--build-system native)
# The Command Line Tools keep Swift Testing outside the SDK, where SwiftPM does not look.
FRAMEWORKS="${COMMAND_LINE_TOOLS}/Library/Developer/Frameworks"
if [ "$(xcode-select -p 2>/dev/null)" = "${COMMAND_LINE_TOOLS}" ] && [ -d "${FRAMEWORKS}/Testing.framework" ]; then
    ARGS+=(-Xswiftc -F -Xswiftc "${FRAMEWORKS}" -Xlinker -rpath -Xlinker "${FRAMEWORKS}")
fi

swift test "${ARGS[@]}" "$@"
