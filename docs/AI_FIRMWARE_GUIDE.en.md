# Use Codex or Claude Code to port and flash NuphyBar firmware

This guide is for a local coding agent that can read the checkout and run terminal commands. A normal web chat cannot inspect a DFU device or flash a keyboard directly.

## Safety boundary

Split the task into two phases:

1. **Agent may execute:** inspect official model data, edit source, add tests, compile, verify hashes, and list DFU devices.
2. **Human confirmation required:** confirm the exact model, export VIA, prepare recovery firmware, enter DFU, and authorize the final flash command.

The agent must never infer a model, reuse an Air60 binary on another Air V2 keyboard, skip hashes/tests, increase RF polling for animation, stream frames over BLE, choose among multiple DFU devices, or run `dfu-util -D` without explicit confirmation.

## Prompt: build and flash the supported Air60 V2

```text
You are working in the NuphyBar repository. The target is a NuPhy Air60 V2 ANSI.

Use the existing stable-v7 source and builder under firmware/air60-v2. Do not rewrite the wireless protocol and do not use an earlier experimental image.

Phase A (authorized now):
1. Read README.md, firmware/air60-v2/README.md, build.sh, and verify_candidate.py.
2. Verify that the NuPhy v2.1.5 input SHA-256 is cd0425f548a01416d1c3c25208ff74867fffd20165520c7c2eaa56000ff347bf.
3. Run firmware/air60-v2/test.sh.
4. Build NuphyBar-Air60-V2-stable-v7.bin with build.sh.
5. Verify output SHA-256 c573c7939a53994b50f29313744f27f9af30b90cd064f13fc019f87710b89ac0.
6. Report tests, input hash, output hash, and the absolute output path.
7. Stop before flashing. Ask me to confirm exactly: “Air60 V2 ANSI is in DFU; flash stable-v7.”

Phase B (only after that exact confirmation):
1. Run dfu-util -l.
2. Continue only if exactly one expected STM32 DFU device is present; otherwise stop.
3. Print the firmware hash again.
4. Run dfu-util -a 0 -s 0x08000000:leave -D <verified firmware>.
5. Check exit status and download/verification output.
6. Ask me to reconnect Bluetooth and verify typing, Caps Lock, idle, working, waiting, and complete.

Stop on any model, hash, or DFU mismatch. Never bypass a guard.
```

## Prompt: port to Air75 V2 or Air96 V2

```text
Port NuphyBar to the exact NuPhy <model and layout>. This is a new model port; never reuse the Air60 V2 binary or fixed addresses.

Keep the standard HID state mapping:
- 0x00 idle / restore stock lighting
- 0x01 working
- 0x04 waiting/error
- 0x05 complete
- 0x02 always remains Caps Lock

Requirements:
1. Confirm from NuPhy's official firmware catalog that this is the QMK model, not NuPhy IO.
2. Obtain the model's official QMK source and recovery firmware; record exact versions and SHA-256.
3. Locate the complete host LED field from the wireless module, link_mode, right-side LED indices, and stock refresh order using source evidence.
4. Prefer a source-level QMK port. Propose a signature-guarded minimal binary hook only if the public source materially differs from the stable official release.
5. Never accelerate RF/UART polling or send a multi-frame protocol. The Mac sends one persistent two-bit state and the keyboard renders locally.
6. Idle and USB must restore stock behavior; the left Caps indicator must remain unchanged.
7. Add host tests for state decoding, seamless effects, LED bounds, and time behavior.
8. Report Flash/RAM delta, final SHA-256, changed files, and recovery procedure.
9. Stop before any physical flash and ask for explicit confirmation of the exact model, layout, recovery image, and DFU state.

“Same Air V2 family” never means “same .bin.” The deliverable is a model-specific image and staged physical verification.
```

## Prompt: design effects for Halo V2 QMK or Gem80

```text
Adapt NuphyBar to the exact NuPhy <model>, but do not imitate the Air60 V2 five-LED bar.

First inspect the actual controllable topology (Halolight, nameplate, side light, or bottom light). Propose three calm but clearly distinguishable local effects for working, waiting/error, and complete. Keep 0x00/0x01/0x04/0x05 as the state protocol and render all animation frames in firmware.

Submit only the effect model and host tests first. Do not change wireless polling and do not flash. Wire it into the model's stock refresh path only after I select an effect direction.
```

## Required pre-flash report

Before asking for authorization, the agent should display:

```text
Keyboard: NuPhy Air60 V2 ANSI
Baseline: NuPhy official v2.1.5
Input SHA-256: cd0425...
Output: /absolute/path/NuphyBar-Air60-V2-stable-v7.bin
Output SHA-256: c573c7...
Tests: all passed
Recovery image: ready
DFU: waiting for the user
Next command: dfu-util ... -D <absolute path>
```

Any missing line blocks the flash.

## Staged verification after flashing

1. Keep NuphyBar closed and type over Bluetooth; verify stock idle lighting and stability.
2. Send one working state and keep typing for several minutes.
3. Verify the amber waiting double pulse.
4. Verify green completion breathing.
5. Send idle and confirm stock rainbow/battery lighting returns.
6. Toggle Caps Lock and confirm the left cyan indicator.
7. Disconnect and reconnect; confirm both typing and NuphyBar recover.

If typing freezes, the light bar stalls, the keyboard disconnects, or sleep breaks, stop and restore the official image. Do not hide the error or increase polling again.
