#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$(mktemp -d /tmp/NuphyBar-firmware-tests.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

PYTHONPATH="$ROOT_DIR" python3 -m unittest discover -s "$ROOT_DIR/tests" -p 'test_*.py'

cc \
  -std=c11 \
  -Wall \
  -Wextra \
  -Werror \
  -I "$ROOT_DIR/src" \
  "$ROOT_DIR/src/effect_model.c" \
  "$ROOT_DIR/tests/test_effect_model.c" \
  -o "$BUILD_DIR/test_effect_model"
"$BUILD_DIR/test_effect_model"
