#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCE_DIR="$ROOT_DIR/Sources/AgentLightApp/Resources"
STAGE_DIR="$(mktemp -d /tmp/NuphyBar-icons.XXXXXX)"
ICONSET_DIR="$STAGE_DIR/NuphyBar.iconset"
SOURCE_PNG="$(mktemp /tmp/NuphyBar-icon.XXXXXX).png"
trap 'rm -rf "$STAGE_DIR" "$SOURCE_PNG"' EXIT

mkdir -p "$RESOURCE_DIR" "$ICONSET_DIR"
sips -s format png "$ROOT_DIR/Design/NuphyBarAppIcon.svg" --out "$SOURCE_PNG" >/dev/null

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SOURCE_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" "$SOURCE_PNG" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$RESOURCE_DIR/NuphyBar.icns"
sips -s format png "$ROOT_DIR/Design/NuphyBarMenuBarIcon.svg" \
  --out "$RESOURCE_DIR/NuphyBarMenuBarIcon.png" >/dev/null
