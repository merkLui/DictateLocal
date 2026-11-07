#!/bin/bash
# Prints the CHANGELOG.md section for a version, for the GitHub release notes.

set -euo pipefail
cd "$(dirname "$0")/../.."
VERSION="${1:?Usage: release-notes.sh <version>}"

NOTES=$(awk -v version="${VERSION}" '
    /^## / { if (found) exit; if (index($0, "[" version "]")) { found = 1; next } }
    found && !/^\[[^]]*\]: / { print }
' CHANGELOG.md)
[ -n "${NOTES}" ] || { echo "CHANGELOG.md has no section for ${VERSION}" >&2; exit 1; }
printf '%s\n\n%s\n' "${NOTES}" "Install with \`brew install --cask merkLui/tap/dictatelocal\` or download the disk image below. See the [README](https://github.com/merkLui/DictateLocal#install) for the first launch."
