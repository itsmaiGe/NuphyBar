# Changelog

## Unreleased

- Added an Antigravity integration using Google's official global plugin and lifecycle Hooks.
- Added an icon derived directly from the official Antigravity macOS app asset for integration identification.

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
