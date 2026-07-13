#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NuphyBar"
APP_VERSION="${APP_VERSION:-0.5.8}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/$APP_NAME-$APP_VERSION-macOS-arm64.dmg"
STAGE_DIR="$(mktemp -d /tmp/NuphyBar-release.XXXXXX)"
trap 'rm -rf "$STAGE_DIR"' EXIT

APP_PATH="$STAGE_DIR/$APP_NAME.app"
IMAGE_DIR="$STAGE_DIR/image"
TEMP_DMG="$STAGE_DIR/$APP_NAME.dmg"

mkdir -p "$DIST_DIR"
"$ROOT_DIR/script/build_app.sh" "$APP_PATH" >/dev/null

mkdir -p "$IMAGE_DIR"
ditto --norsrc --noextattr --noqtn --noacl "$APP_PATH" "$IMAGE_DIR/$APP_NAME.app"
ln -s /Applications "$IMAGE_DIR/Applications"

rm -f "$DMG_PATH"
codesign --verify --deep --strict "$APP_PATH"
diskutil image create from \
  --volumeName "$APP_NAME" \
  --format UDZO \
  "$IMAGE_DIR" \
  "$TEMP_DMG" >/dev/null
ditto --norsrc --noextattr --noqtn --noacl "$TEMP_DMG" "$DMG_PATH"
hdiutil verify "$DMG_PATH" >/dev/null
shasum -a 256 "$DMG_PATH"
