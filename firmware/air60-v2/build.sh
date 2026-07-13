#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFICIAL_FIRMWARE="${1:-}"
OUTPUT="${2:-$ROOT_DIR/build/NuphyBar-Air60-V2-stable-v7.bin}"
BUILD_DIR="$(mktemp -d /tmp/NuphyBar-air60-v2.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

if [ -z "$OFFICIAL_FIRMWARE" ] || [ ! -f "$OFFICIAL_FIRMWARE" ]; then
  echo "usage: $0 /path/to/QMK_firmware_nuphy_air60_v2_ansi_v2.1.5.bin [output.bin]" >&2
  exit 2
fi

find_tool() {
  local name="$1"
  local formula="${2:-}"
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return
  fi
  if command -v brew >/dev/null 2>&1 && [ -n "$formula" ]; then
    local prefix
    prefix="$(brew --prefix "$formula" 2>/dev/null || true)"
    if [ -x "$prefix/bin/$name" ]; then
      echo "$prefix/bin/$name"
      return
    fi
  fi
  echo "missing tool: $name" >&2
  exit 1
}

ARM_GCC="$(find_tool arm-none-eabi-gcc arm-none-eabi-gcc@8)"
ARM_OBJCOPY="$(find_tool arm-none-eabi-objcopy arm-none-eabi-binutils)"
DFU_SUFFIX="$(find_tool dfu-suffix dfu-util)"

"$ROOT_DIR/test.sh"

COMMON_FLAGS=(
  -mcpu=cortex-m0
  -mthumb
  -Os
  -ffreestanding
  -fno-builtin
  -ffunction-sections
  -fdata-sections
  -I "$ROOT_DIR/src"
)

"$ARM_GCC" "${COMMON_FLAGS[@]}" \
  -c "$ROOT_DIR/src/agent_light_hook.c" \
  -o "$BUILD_DIR/agent_light_hook.o"
"$ARM_GCC" "${COMMON_FLAGS[@]}" \
  -c "$ROOT_DIR/src/effect_model.c" \
  -o "$BUILD_DIR/effect_model.o"
"$ARM_GCC" \
  -mcpu=cortex-m0 \
  -mthumb \
  -nostdlib \
  -Wl,-T,"$ROOT_DIR/src/agent_light_hook.ld" \
  -Wl,--gc-sections \
  -Wl,-Map,"$BUILD_DIR/agent_light_hook.map" \
  -o "$BUILD_DIR/agent_light_hook.elf" \
  "$BUILD_DIR/agent_light_hook.o" \
  "$BUILD_DIR/effect_model.o"
"$ARM_OBJCOPY" -O binary \
  "$BUILD_DIR/agent_light_hook.elf" \
  "$BUILD_DIR/agent_light_hook.bin"

mkdir -p "$(dirname "$OUTPUT")"
DFU_SUFFIX="$DFU_SUFFIX" python3 "$ROOT_DIR/build_candidate.py" \
  --official "$OFFICIAL_FIRMWARE" \
  --hook "$BUILD_DIR/agent_light_hook.bin" \
  --output "$OUTPUT"
python3 "$ROOT_DIR/verify_candidate.py" \
  --official "$OFFICIAL_FIRMWARE" \
  --candidate "$OUTPUT" \
  --hook "$BUILD_DIR/agent_light_hook.bin"

echo "Firmware: $OUTPUT"
shasum -a 256 "$BUILD_DIR/agent_light_hook.bin" "$OUTPUT"
