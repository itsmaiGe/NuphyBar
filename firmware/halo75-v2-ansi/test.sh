#!/usr/bin/env bash
set -euo pipefail

FIRMWARE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$(mktemp -d /tmp/NuphyBar-halo75-tests.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

python3 -m unittest discover -s "$FIRMWARE_DIR/tests" -p 'test_*.py'

cc \
  -std=c11 \
  -Wall \
  -Wextra \
  -Werror \
  -I "$FIRMWARE_DIR/src" \
  "$FIRMWARE_DIR/src/effect_model.c" \
  "$FIRMWARE_DIR/tests/test_effect_model.c" \
  -o "$BUILD_DIR/test_effect_model"
"$BUILD_DIR/test_effect_model"
