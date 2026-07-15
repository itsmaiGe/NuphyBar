#!/usr/bin/env python3
"""Verify that a candidate changes only the audited call site and appended hook.

SPDX-License-Identifier: GPL-2.0-or-later
Copyright 2026 Maige
"""

from __future__ import annotations

import argparse
import pathlib

from build_candidate import CALL_SITE, FLASH_BASE, HOOK_ADDRESS, encode_thumb_bl


def without_dfu_suffix(data: bytes) -> bytes:
    if data[-8:-5] != b"UFD" or data[-5] != 16:
        raise ValueError("missing 16-byte DFU suffix")
    return data[:-16]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official", type=pathlib.Path, required=True)
    parser.add_argument("--candidate", type=pathlib.Path, required=True)
    parser.add_argument("--hook", type=pathlib.Path, required=True)
    args = parser.parse_args()

    official = without_dfu_suffix(args.official.read_bytes())
    candidate = without_dfu_suffix(args.candidate.read_bytes())
    hook = args.hook.read_bytes()
    call_offset = CALL_SITE - FLASH_BASE
    hook_offset = HOOK_ADDRESS - FLASH_BASE

    expected_call = encode_thumb_bl(CALL_SITE, HOOK_ADDRESS)
    require(candidate[call_offset : call_offset + 4] == expected_call, "candidate call site mismatch")
    require(candidate[:call_offset] == official[:call_offset], "candidate prefix differs from official firmware")
    require(
        candidate[call_offset + 4 : len(official)] == official[call_offset + 4 :],
        "candidate official firmware region was modified",
    )
    require(
        candidate[len(official) : hook_offset] == b"\xFF" * (hook_offset - len(official)),
        "candidate padding before hook is not erased flash",
    )
    require(candidate[hook_offset:] == hook, "candidate hook payload mismatch")
    require(len(candidate) == hook_offset + len(hook), "candidate length mismatch")
    print("candidate layout verified")


if __name__ == "__main__":
    main()
