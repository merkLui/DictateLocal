#!/bin/bash
# Points the Homebrew cask in merkLui/homebrew-tap at the new release.

set -euo pipefail
cd "$(dirname "$0")/../.."
: "${VERSION:?set VERSION}"
: "${TAP_DEPLOY_KEY:?missing secret TAP_DEPLOY_KEY}"

SHA=$(cut -d' ' -f1 "dist/DictateLocal-${VERSION}.zip.sha256")
KEY="${RUNNER_TEMP}/tap_key"
printf '%s\n' "${TAP_DEPLOY_KEY}" > "${KEY}"
chmod 600 "${KEY}"
export GIT_SSH_COMMAND="ssh -i ${KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

TAP="${RUNNER_TEMP}/homebrew-tap"
git clone --depth 1 git@github.com:merkLui/homebrew-tap.git "${TAP}"
CASK="${TAP}/Casks/dictatelocal.rb"
sed -i '' -E "s/^  version \".*\"/  version \"${VERSION}\"/; s/^  sha256 \".*\"/  sha256 \"${SHA}\"/" "${CASK}"

cd "${TAP}"
if git diff --quiet; then
    echo "Cask already at ${VERSION}"
    exit 0
fi
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git commit -am "dictatelocal ${VERSION}"
git push origin HEAD
rm -f "${KEY}"
