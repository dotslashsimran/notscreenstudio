#!/usr/bin/env bash
# Builds the release app and packs it into dist/notscreenstudio-<version>-macos.zip plus a .sha256 file.
# Usage: scripts/package.sh [version]     (version defaults to the current git tag, for example v0.1.0)
# Optional environment:
#   NSS_ARCHS            Architectures to build, default "arm64 x86_64" (universal). Use "arm64" for one.
#   NSS_DIST_DIR         Output folder, default dist
#   NSS_BUILD_DIR        Where the .app is built, default build
#   NSS_JOBS, NSS_SKIP_SMOKE   As in bundle.sh
#   NSS_SIGN_IDENTITY    Signing identity. With NSS_HARDENED=1 it signs with the hardened runtime.
#   NSS_NOTARY_PROFILE   notarytool keychain profile. When set, the zip is notarized and the app stapled.
#   NSS_NOTARY_KEYCHAIN  Optional keychain file that holds the profile (default: the login keychain).
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="NotScreenStudio"

RAW="${1:-$(git describe --tags --exact-match 2>/dev/null || true)}"
[ -n "$RAW" ] || { echo "Usage: $0 <version>   (or run on a tagged commit)" >&2; exit 1; }
VERSION="${RAW#v}"
case "$VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "Version must look like 1.2.3 or v1.2.3 (got: $RAW)" >&2; exit 1 ;;
esac
# CFBundleVersion must be dotted numbers only, so drop any suffix such as -rc1.
BUILD_NUMBER="${VERSION%%[-+]*}"

DIST="${NSS_DIST_DIR:-dist}"
BUILD_DIR="${NSS_BUILD_DIR:-build}"
APP="${BUILD_DIR}/${APP_NAME}.app"
ZIP="${DIST}/notscreenstudio-${VERSION}-macos.zip"

export NSS_VERSION="${VERSION%%[-+]*}"
export NSS_BUILD_NUMBER="$BUILD_NUMBER"
export NSS_OUT_DIR="$BUILD_DIR"
export NSS_ARCHS="${NSS_ARCHS:-arm64 x86_64}"
# Releases are ad hoc signed unless an identity is given (never the local notscreenstudio-dev identity).
export NSS_SIGN_IDENTITY="${NSS_SIGN_IDENTITY:--}"
if [ "$NSS_SIGN_IDENTITY" != "-" ]; then export NSS_HARDENED=1; fi

./scripts/bundle.sh

mkdir -p "$DIST"
rm -f "$ZIP" "$ZIP.sha256"

if [ -n "${NSS_NOTARY_PROFILE:-}" ]; then
  [ "$NSS_SIGN_IDENTITY" != "-" ] || { echo "Notarization needs NSS_SIGN_IDENTITY" >&2; exit 1; }
  SUBMIT_ZIP="$(mktemp -d)/submit.zip"
  ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"
  NOTARY_ARGS=(--keychain-profile "$NSS_NOTARY_PROFILE")
  if [ -n "${NSS_NOTARY_KEYCHAIN:-}" ]; then NOTARY_ARGS+=(--keychain "$NSS_NOTARY_KEYCHAIN"); fi
  xcrun notarytool submit "$SUBMIT_ZIP" "${NOTARY_ARGS[@]}" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
fi

# ditto keeps the bundle, its signature and any stapled ticket intact (plain zip can break them).
ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")

echo "Packaged $ZIP"
cat "$ZIP.sha256"
