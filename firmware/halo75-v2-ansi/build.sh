#!/usr/bin/env bash
set -euo pipefail

FIRMWARE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$FIRMWARE_DIR/../.." && pwd)"
SOURCE_ROOT="${1:?usage: build.sh /path/to/nuphy-qmk-source}"
BASELINE_COMMIT="4223dece7852b9fd9abd7c61559272241ef4a223"
BUILD_ROOT="$(mktemp -d /tmp/NuphyBar-halo75-build.XXXXXX)"
BUILD_ROOT="$(cd "$BUILD_ROOT" && pwd -P)"
QMK_ROOT="$BUILD_ROOT/qmk_firmware"
OUTPUT_NAME="NuphyBar-Halo75-V2-ANSI.bin"
QMK_DOCKER_IMAGE="qmkfm/qmk_cli@sha256:b7d7fa8fb4432b569931de5ad59098cb788f440ed61a62c5126746b71aee0f4a"

cleanup() {
  git -C "$SOURCE_ROOT" worktree remove --force "$QMK_ROOT" >/dev/null 2>&1 || true
  rmdir "$BUILD_ROOT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

git -C "$SOURCE_ROOT" worktree add --quiet --detach "$QMK_ROOT" "$BASELINE_COMMIT"
git -C "$QMK_ROOT" submodule update --init --recursive
python3 "$FIRMWARE_DIR/install.py" "$QMK_ROOT"

if command -v qmk >/dev/null 2>&1; then
  (cd "$QMK_ROOT" && qmk compile -kb nuphy/halo75_v2/ansi -km via -j 2 -e SKIP_VERSION=yes)
elif command -v docker >/dev/null 2>&1; then
  docker run --rm \
    --volume "$QMK_ROOT:$QMK_ROOT" \
    --volume "$SOURCE_ROOT:$SOURCE_ROOT" \
    --workdir "$QMK_ROOT" \
    "$QMK_DOCKER_IMAGE" \
    bash -lc \
    '/opt/uv/tools/qmk/bin/python3 -m pip install --quiet -r requirements.txt && export PATH="/opt/uv/tools/qmk/bin:$PATH" && qmk compile -kb nuphy/halo75_v2/ansi -km via -j 2 -e SKIP_VERSION=yes'
else
  echo "Install QMK CLI or Docker to build the firmware." >&2
  exit 1
fi

cp "$QMK_ROOT/nuphy_halo75_v2_ansi_via.bin" "$REPOSITORY_ROOT/$OUTPUT_NAME"
shasum -a 256 "$REPOSITORY_ROOT/$OUTPUT_NAME"
