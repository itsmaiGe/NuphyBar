#!/usr/bin/env python3
"""Build the audited NuphyBar patch on NuPhy Air60 V2 firmware v2.1.5.

SPDX-License-Identifier: GPL-2.0-or-later
Copyright 2026 Maige
"""

from __future__ import annotations

import argparse
import hashlib
import os
import pathlib
import struct
import subprocess


EXPECTED_OFFICIAL_SHA256 = "cd0425f548a01416d1c3c25208ff74867fffd20165520c7c2eaa56000ff347bf"
FLASH_BASE = 0x08000000
CALL_SITE = 0x080028EA
ORIGINAL_CALL = bytes.fromhex("ff f7 5b fd")
HOOK_ADDRESS = 0x08010E00
VERIFIED_SIGNATURES = {
    0x08000290: bytes.fromhex("00 29 f8 d0 03 b5 ff f7 c1 ff 0e bc 42 43 89 1a 18 47"),
    0x080023A4: bytes.fromhex("09 4b 10 b5 1a 78 02 24 04 2a"),
    0x08007E38: bytes.fromhex("10 b5 02 4c 64 68 a0 47 10 bd"),
    0x0800B2E8: bytes.fromhex("70 b5 72 b6 01 f0 82 fa 11 4c"),
}


def encode_thumb_bl(instruction_address: int, target_address: int) -> bytes:
    offset = target_address - (instruction_address + 4)
    if offset % 2 != 0 or not -(1 << 22) <= offset < (1 << 22):
        raise ValueError("Thumb BL target is unaligned or out of range")
    first = 0xF000 | ((offset >> 12) & 0x7FF)
    second = 0xF800 | ((offset >> 1) & 0x7FF)
    return struct.pack("<HH", first, second)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official", type=pathlib.Path, required=True)
    parser.add_argument("--hook", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()

    official = args.official.read_bytes()
    digest = hashlib.sha256(official).hexdigest()
    if digest != EXPECTED_OFFICIAL_SHA256:
        raise SystemExit(f"unexpected official firmware SHA-256: {digest}")
    if official[-8:-5] != b"UFD" or official[-5] != 16:
        raise SystemExit("official firmware has no valid 16-byte DFU suffix")

    payload = bytearray(official[:-16])
    for address, signature in VERIFIED_SIGNATURES.items():
        offset = address - FLASH_BASE
        if payload[offset : offset + len(signature)] != signature:
            raise SystemExit(f"official function signature mismatch at 0x{address:08x}")

    call_offset = CALL_SITE - FLASH_BASE
    if payload[call_offset : call_offset + 4] != ORIGINAL_CALL:
        raise SystemExit("official call site bytes do not match the verified v2.1.5 image")

    payload[call_offset : call_offset + 4] = encode_thumb_bl(CALL_SITE, HOOK_ADDRESS)
    hook = args.hook.read_bytes()
    hook_offset = HOOK_ADDRESS - FLASH_BASE
    if len(payload) > hook_offset:
        raise SystemExit("hook address overlaps official firmware payload")
    payload.extend(b"\xFF" * (hook_offset - len(payload)))
    payload.extend(hook)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(payload)
    subprocess.run(
        [
            os.environ.get("DFU_SUFFIX", "dfu-suffix"),
            "--vid",
            "0x0483",
            "--pid",
            "0xdf11",
            "--did",
            "0xffff",
            "--spec",
            "0x0100",
            "--add",
            str(args.output),
        ],
        check=True,
    )


if __name__ == "__main__":
    main()
