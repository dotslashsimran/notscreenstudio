#!/usr/bin/env bash
# Builds a release binary and wraps it into build/NotScreenStudio.app (ad-hoc signed).
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="NotScreenStudio"
BUNDLE_ID="dev.notscreenstudio.app"
APP="build/${APP_NAME}.app"

JOBS="${NSS_JOBS:-2}"
swift build -c release -j "$JOBS"
BIN="$(swift build -c release --show-bin-path)/${APP_NAME}"

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
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCameraUsageDescription</key><string>notscreenstudio records your camera for the camera bubble. Video never leaves your Mac.</string>
  <key>NSMicrophoneUsageDescription</key><string>notscreenstudio records your microphone for narration. Audio never leaves your Mac.</string>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"
codesign --verify --verbose "$APP"
# Non-interactive launch check: builds every dependency and renders one frame, then exits 0.
# Set NSS_SKIP_SMOKE=1 to skip it (for example over SSH without a GUI session).
if [ "${NSS_SKIP_SMOKE:-0}" != "1" ]; then
  "$APP/Contents/MacOS/${APP_NAME}" --smoke-test
fi
echo "Built $APP"
