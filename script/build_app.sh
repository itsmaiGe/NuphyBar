#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NuphyBar"
BUNDLE_ID="com.maige.NuphyBar"
APP_VERSION="${APP_VERSION:-0.5.9}"
BUILD_VERSION="${BUILD_VERSION:-25}"
MIN_SYSTEM_VERSION="14.0"
DESIGNATED_REQUIREMENT="designated => identifier \"$BUNDLE_ID\""

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_APP="${1:-$ROOT_DIR/dist/$APP_NAME.app}"

if [ "$(basename "$OUTPUT_APP")" != "$APP_NAME.app" ]; then
  echo "output must end in $APP_NAME.app" >&2
  exit 2
fi

APP_CONTENTS="$OUTPUT_APP/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_HELPERS="$APP_CONTENTS/Helpers"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

cd "$ROOT_DIR"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$OUTPUT_APP"
mkdir -p "$APP_MACOS" "$APP_HELPERS" "$APP_RESOURCES"
cp "$BIN_DIR/$APP_NAME" "$APP_BINARY"
cp "$BIN_DIR/agent-light" "$APP_HELPERS/agent-light"
cp "$ROOT_DIR/Sources/AgentLightApp/Resources/NuphyBar.icns" "$APP_RESOURCES/NuphyBar.icns"
cp "$ROOT_DIR/Sources/AgentLightApp/Resources/NuphyBarMenuBarIcon.png" "$APP_RESOURCES/NuphyBarMenuBarIcon.png"

for asset in Codex.png ClaudeCode.png Antigravity.png GrokBuild.svg Hermes.png OpenClaw.png; do
  cp "$ROOT_DIR/Sources/AgentLightApp/Resources/AgentIcons/$asset" "$APP_RESOURCES/$asset"
done

chmod +x "$APP_BINARY" "$APP_HELPERS/agent-light"
strip -x "$APP_BINARY" "$APP_HELPERS/agent-light"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>NuphyBar</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_VERSION</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSInputMonitoringUsageDescription</key>
  <string>NuphyBar sends status to compatible NuPhy Bluetooth keyboards. It never reads or stores keystrokes.</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Maige</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_HELPERS/agent-light"
codesign --force --sign - --requirements "=$DESIGNATED_REQUIREMENT" "$OUTPUT_APP"
codesign --verify --deep --strict "$OUTPUT_APP"

echo "$OUTPUT_APP"
