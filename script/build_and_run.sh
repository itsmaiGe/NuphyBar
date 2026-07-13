#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="NuphyBar"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE_DIR="$(mktemp -d /tmp/AgentLight-build.XXXXXX)"
trap 'rm -rf "$STAGE_DIR"' EXIT

APP_BUNDLE="$STAGE_DIR/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
INSTALL_APP="$INSTALL_DIR/$APP_NAME.app"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x "AgentLight" >/dev/null 2>&1 || true

"$ROOT_DIR/script/build_app.sh" "$APP_BUNDLE" >/dev/null

mkdir -p "$INSTALL_DIR"
INSTALL_STAGE_DIR="$(mktemp -d "$INSTALL_DIR/.NuphyBar-install.XXXXXX")"
INSTALL_CANDIDATE="$INSTALL_STAGE_DIR/$APP_NAME.app"
PREVIOUS_APP="$INSTALL_STAGE_DIR/previous.app"
INSTALL_COMMITTED=0
INSTALL_SWAP_STARTED=0

cleanup_install() {
  if [ "$INSTALL_SWAP_STARTED" -eq 1 ] && [ "$INSTALL_COMMITTED" -eq 0 ]; then
    rm -rf "$INSTALL_APP"
    if [ -d "$PREVIOUS_APP" ]; then
      mv "$PREVIOUS_APP" "$INSTALL_APP"
    fi
  fi
  rm -rf "$INSTALL_STAGE_DIR"
}
trap 'cleanup_install; rm -rf "$STAGE_DIR"' EXIT

ditto --norsrc --noextattr --noqtn --noacl "$APP_BUNDLE" "$INSTALL_CANDIDATE"
codesign --verify --deep --strict "$INSTALL_CANDIDATE"
if [ -d "$INSTALL_APP" ]; then
  mv "$INSTALL_APP" "$PREVIOUS_APP"
fi
INSTALL_SWAP_STARTED=1
mv "$INSTALL_CANDIDATE" "$INSTALL_APP"
codesign --verify --deep --strict "$INSTALL_APP"
INSTALL_COMMITTED=1

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$INSTALL_APP" >/dev/null 2>&1 || true

LEGACY_APPS=(
  "$HOME/Applications/AgentLight.app"
  "/Applications/AgentLight.app"
  "/Applications/NuphyBar.app"
)
for legacy_app in "${LEGACY_APPS[@]}"; do
  if [ -d "$legacy_app" ]; then
    "$LSREGISTER" -u "$legacy_app" >/dev/null 2>&1 || true
    rm -rf "$legacy_app"
  fi
done

open_app() {
  /usr/bin/open -n "$INSTALL_APP"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$INSTALL_APP/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.maige.NuphyBar"'
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
