# Contributing

Thanks for helping improve NuphyBar.

## Before changing code

1. Open an issue describing the exact NuPhy model, layout, connection mode, and firmware track (QMK or NuPhy IO).
2. Never assume that two Air/Halo sizes share LED indices or a flashable binary.
3. Keep Mac-to-keyboard traffic state-based. Animation belongs in firmware; do not stream frames over BLE or accelerate the stock RF polling loop.

## App checks

```bash
swift test
swift build -c release
bash -n script/*.sh firmware/air60-v2/*.sh
```

## Air60 V2 firmware checks

```bash
./firmware/air60-v2/test.sh
./firmware/air60-v2/build.sh /path/to/official-v2.1.5.bin
```

The Release firmware must reproduce SHA-256 `c573c7939a53994b50f29313744f27f9af30b90cd064f13fc019f87710b89ac0` with the documented GCC 8.5.0 toolchain.

## New keyboard ports

A port is not “supported” until it has:

- an exact model and layout;
- an official source/recovery baseline with hashes;
- model-specific LED indices or audited function signatures;
- tests for state decoding and effects;
- a dedicated output filename that includes the model;
- staged physical verification of typing, Caps Lock, every state, reconnect, sleep, and recovery.

Do not include user VIA backups, full-flash dumps, old experiments, official recovery binaries, or local Agent configuration in a pull request.

## Licensing

App changes are MIT. Firmware changes derived from QMK/NuPhy must remain GPL-2.0-or-later and retain relevant copyright notices. Third-party logos must include a primary source and must not be presented as project-owned artwork.
