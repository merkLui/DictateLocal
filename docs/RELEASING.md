# Releasing

Releases are built, signed and published by [the release workflow](../.github/workflows/release.yml) when a version tag is pushed.

## Cutting a release

1. Move the entries under `## [Unreleased]` in `CHANGELOG.md` into a new `## [x.y.z] - YYYY-MM-DD` section and update the links at the bottom.
2. Commit with `chore: release x.y.z` and merge it to `main`.
3. Tag and push:

   ```bash
   git tag -a vx.y.z -m "DictateLocal x.y.z"
   git push origin vx.y.z
   ```

The workflow then runs the tests, signs the app with the release certificate, packs it into a drag-to-install disk image with [dmgbuild](https://github.com/dmgbuild/dmgbuild), uploads `DictateLocal-x.y.z.dmg` with its SHA-256 to a GitHub release whose notes come from the changelog, and updates the cask in [merkLui/homebrew-tap](https://github.com/merkLui/homebrew-tap).

## Signing

DictateLocal is not in the Apple Developer Program, so releases are not notarized and the first launch of a download needs the user's approval (see the README). They are still signed with a self-signed certificate, "DictateLocal Release", so that macOS recognizes every update as the same app and keeps its permissions.

The certificate lives only in two repository secrets:

| Secret | Contents |
| --- | --- |
| `SIGNING_CERTIFICATE_P12` | The certificate and private key as a base64-encoded `.p12` |
| `SIGNING_CERTIFICATE_PASSWORD` | The `.p12` password |

Keep a backup of the `.p12` and its password in a password manager. A new certificate would make every user grant the permissions again.

To create it from scratch (only if it is lost):

```bash
scripts/create-signing-certificate.sh --export release.p12 "DictateLocal Release"
```

and follow the printed `gh secret set` commands, then move `release.p12` and `release.password` into a password manager and delete them.

## Homebrew

The cask lives in [merkLui/homebrew-tap](https://github.com/merkLui/homebrew-tap) as `Casks/dictatelocal.rb`. The workflow pushes the new version and checksum with a deploy key that can only write to that repository; its private half is the `TAP_DEPLOY_KEY` secret.
