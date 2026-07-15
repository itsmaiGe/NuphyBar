# Changelog

## Unreleased

## 0.5.9 — 2026-07-15

### App

- Added an Antigravity integration using Google's official global plugin and lifecycle Hooks, with an icon derived from the official macOS app asset.
- Replaced one-second Agent-state polling with macOS system notifications and exact expiration timers; a five-second fallback remains if notification registration fails.
- Replaced repeated HID scanning and per-command device opens with a persistent non-exclusive HID manager driven by connection and removal callbacks.
- Added bounded HID session recovery after report failures and proactive session rebuilding after Mac wake, with automatic replay of the latest Agent state when delivery is ready again.
- Coalesced Agent events that arrive during an in-flight HID report into one immediate follow-up refresh.
- Changed terminal error retention from 15 minutes to about 15 seconds, matching completion behavior.
- Removed unused source and icon assets, simplified state/effect logic, and stripped local symbols from Release binaries.

### Firmware tooling

- Replaced Python `assert`-based candidate checks with verification that remains active under optimized Python execution.
- Added a regression test proving invalid firmware candidates are rejected with `python -O`.

## 0.5.8 — 2026-07-14

### App

- Added the native NuphyBar macOS menu-bar app and compact settings window.
- Added local integrations for Codex, Claude Code, OpenCode, Grok Build, Hermes, and OpenClaw.
- Added multi-session state aggregation with error/waiting, working, complete, and idle priority.
- Added BLE NuPhy device discovery, serialized HID delivery, reconnect recovery, launch at login, Chinese/English UI, and official integration brand assets.
- Removed animation streaming: the Mac now sends only one persistent LED state report when the state changes.

### Firmware

- Added the physically verified Air60 V2 ANSI `stable-v7` minimal patch on NuPhy official v2.1.5.
- Preserved the stock Caps Lock indicator and idle lighting.
- Added local blue working wave, amber waiting double pulse, and green completion breathing effects.
- Added machine-code baseline guards, deterministic patch layout verification, effect tests, and a reproducible builder.
