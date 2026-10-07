# Halo75 V2 ANSI USB and Bluetooth firmware

This port targets only the NuPhy Halo75 V2 ANSI QMK keyboard. It controls the five LEDs in the upper-left status light at RGB Matrix indices 83 through 87 over wired USB and Bluetooth Low Energy. Do not flash its output on an ISO keyboard, another Halo size, or a NuPhy IO model.

The source baseline is NuPhy's official `nuphy-src/qmk_firmware` commit `4223dece7852b9fd9abd7c61559272241ef4a223`, dated 2025-03-25. The audited Halo75 V2 ANSI tree is `601063bb3bf91073d364063e69fedddbbef1e049`. NuPhy's official Halo75 V2 ANSI v2.1.5 recovery image has SHA-256 `4393adb563b93051552af1161a9f3c460d549adea413e1dca3ab8a27505d61c0`.

Over USB, the app sends one checksummed 32-byte Raw HID report when the state changes and renews active states every five minutes, before the firmware's fifteen-minute timeout. Idle and terminal states are not periodically renewed. The USB product string is changed to `NuPhy Halo75 V2 NuphyBar`, so the app never mistakes stock firmware for a compatible device. Over Bluetooth, the app sends one standard two-byte keyboard LED Output Report and the firmware reads the host mask from NuPhy's existing `dev_info.rf_led` field. The host owns Bluetooth state expiry because repeated Output Reports with the same value are indistinguishable from an unchanged radio state inside the keyboard firmware. All animation frames are rendered locally and the stock Halolight returns while idle.

| State | Upper-left light |
| --- | --- |
| Idle | Stock effect |
| Thinking | Slow red breathing |
| Tool running | Solid red |
| Outputting | Slow yellow breathing |
| Permission required | Fast blue breathing |
| Complete | Solid green |
| Error | Fast red flashing |

Bluetooth safely compresses those states:

| Bluetooth state | Upper-left light |
| --- | --- |
| Idle | Stock effect |
| Working | Slow red breathing |
| Waiting/error | Fast blue breathing |
| Complete | Solid green |

The Caps Lock bit is ignored by the Agent decoder and remains available to the stock Caps indicator. Battery, charging, sleep, pairing, and radio effects still run after the Agent overlay and retain priority. BLE1, BLE2, and BLE3 are enabled. The 2.4 GHz transport remains unchanged and does not show Agent states.

With ordinary Codex Hooks, `UserPromptSubmit` and `PostToolUse` map to thinking, `PreToolUse` maps to tool running, `PermissionRequest` maps to permission required, and `Stop` maps to complete. Hooks do not expose streamed response deltas, so outputting is available in the protocol and CLI but is not inferred from `PostToolUse`.

Run the host-side model tests with:

```bash
./firmware/halo75-v2-ansi/test.sh
```

Build from an official NuPhy QMK checkout with:

```bash
./firmware/halo75-v2-ansi/build.sh /path/to/nuphy-src/qmk_firmware
```

The dedicated output is `NuphyBar-Halo75-V2-ANSI.bin` in the repository root. Before physical testing, retain the existing VIA backup and official Halo75 V2 ANSI recovery firmware. Flashing requires a separate explicit confirmation.

The pinned Docker toolchain produces a 67,922-byte QMK payload and a 67,940-byte DFU image with SHA-256:

```text
a3d3ae63b2d69029222db2cf6427a727261e6a6538218f621d6ede0dfb7e658c
```

Two clean builds produced the same file byte for byte. The USB-only predecessor has a 67,718-byte payload, so Bluetooth support adds 204 bytes and no reported `.data` or `.bss`. The dual-transport build passed USB regression and core Bluetooth physical verification on the same keyboard on 2026-08-28. Verified Bluetooth behavior includes typing, Caps Lock, working, waiting/error, complete, idle restoration, and keyboard power-cycle reconnection. NuphyBar reopened the BLE HID session and resent state with zero output-report errors. Later contributor testing covered sustained typing and cross-day wake/use, as recorded in [recovery validation](../../docs/recovery-validation.md). The remaining release checks are ten controlled Mac sleep/wake cycles, twenty physical reconnect cycles, BLE2/BLE3 switching, and a final complete USB/VIA/idle regression. The recovery image and VIA backup are documented as available; this is not a claim that a new physical recovery test was performed during maintainer review. This port remains experimental pending those checks.
