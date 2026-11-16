#!/usr/bin/env bash
# Builds a release binary and wraps it into build/NotScreenStudio.app (ad-hoc signed).
# Optional: NSS_OUT_DIR, NSS_VERSION, NSS_BUILD_NUMBER, NSS_ARCHS, NSS_HARDENED (see scripts/package.sh).
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="NotScreenStudio"
BUNDLE_ID="dev.notscreenstudio.app"
OUT_DIR="${NSS_OUT_DIR:-build}"
APP="${OUT_DIR}/${APP_NAME}.app"
# Release packaging (scripts/package.sh) sets these. Defaults keep the local build unchanged.
VERSION="${NSS_VERSION:-0.1.0}"
BUILD_NUMBER="${NSS_BUILD_NUMBER:-1}"

JOBS="${NSS_JOBS:-2}"
if [ -n "${NSS_ARCHS:-}" ]; then
  # Space separated list, for example "arm64 x86_64". One build per architecture, joined with lipo.
  BINS=()
  for ARCH in $NSS_ARCHS; do
    swift build -c release -j "$JOBS" --triple "${ARCH}-apple-macosx15.0"
    BINS+=("$(swift build -c release --triple "${ARCH}-apple-macosx15.0" --show-bin-path)/${APP_NAME}")
  done
  BIN="$(mktemp -d)/${APP_NAME}"
  lipo -create "${BINS[@]}" -output "$BIN"
  lipo -info "$BIN"
else
  swift build -c release -j "$JOBS"
  BIN="$(swift build -c release --show-bin-path)/${APP_NAME}"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/${APP_NAME}"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>notscreenstudio</string>
  <key>CFBundleDisplayName</key><string>notscreenstudio</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCameraUsageDescription</key><string>notscreenstudio records your camera for the camera bubble. Video never leaves your Mac.</string>
  <key>NSMicrophoneUsageDescription</key><string>notscreenstudio records your microphone for narration. Audio never leaves your Mac.</string>
</dict>
</plist>
PLIST

# Signing identity: NSS_SIGN_IDENTITY if set, else a "notscreenstudio-dev" identity if the keychain has one
# (create it once with scripts/make-dev-cert.sh), else ad hoc. A stable identity keeps Screen Recording,
# Camera and Microphone permission across rebuilds. This script never creates keychain items.
SIGN_ID="${NSS_SIGN_IDENTITY:-}"
if [ -z "$SIGN_ID" ]; then
  # Capture first: `grep -q` closing the pipe early would trip pipefail. -v lists only identities codesign accepts.
  IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  case "$IDENTITIES" in
    *'"notscreenstudio-dev"'*) SIGN_ID="notscreenstudio-dev" ;;
  esac
fi
if [ "${NSS_HARDENED:-0}" = "1" ]; then
  # Developer ID release: hardened runtime, secure timestamp and the entitlements file (needed for notarization).
  [ -n "$SIGN_ID" ] || { echo "NSS_HARDENED=1 needs NSS_SIGN_IDENTITY" >&2; exit 1; }
  echo "Signing with identity: $SIGN_ID (hardened runtime)"
  codesign --force --deep --options runtime --timestamp \
    --entitlements "${NSS_ENTITLEMENTS:-scripts/entitlements.plist}" -s "$SIGN_ID" "$APP"
elif [ -n "$SIGN_ID" ]; then
  echo "Signing with identity: $SIGN_ID"
  codesign --force --deep -s "$SIGN_ID" "$APP"
else
  echo "Signing ad hoc (permissions may reset after each rebuild; see README > Permissions)"
  codesign --force --deep -s - "$APP"
fi
codesign --verify --verbose "$APP"
# Non-interactive launch check: builds every dependency and renders one frame, then exits 0.
# Set NSS_SKIP_SMOKE=1 to skip it (for example over SSH without a GUI session).
if [ "${NSS_SKIP_SMOKE:-0}" != "1" ]; then
  "$APP/Contents/MacOS/${APP_NAME}" --smoke-test
fi
echo "Built $APP"
