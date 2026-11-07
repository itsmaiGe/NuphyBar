# Changelog

## Unreleased

- Preserve verified Claude endings when a dequeue only writes a linked background task notification to the transcript.

- Recover Claude task anchors across bounded log pages instead of requiring a whole turn in the final two MiB. Validate one unchanged file version through completion, discard progress after file changes, rebuild after restart, and follow nonterminal API-retry metadata without treating it as completion.
- Verify Claude completion through its parent chain when attached response metadata has a later timestamp than the response. Preserve hook/request time fences, pending-tool checks and rejection of unrelated or subsequent activity.
- Handle Claude Code StopFailure and verify ending hooks against bounded root-session evidence. Reconcile missed endings while the owner remains alive, preserve newer requests and long tasks, and ignore subagent endings. Share snapshot inspection with Codex without changing its cleanup rules.
- Track successful NuPhy and AULA writes even when the desired state changes during confirmation, preventing stuck completion lights and duplicate sends after revision-only updates. Preserve old-connection rejection and AULA pause checks.
- Reconcile missed Codex ending hooks against bounded local lifecycle evidence even while the shared agent process remains alive; keep active work when evidence is missing, malformed, or superseded by an unfinished turn.
- Added experimental Halo75 V2 ANSI QMK support over USB Raw HID and Bluetooth, with a separate source overlay and model-specific recovery documentation.
- Added experimental AULA F99 Pro Bluetooth lighting using temporary stock RGB commands, secure-input/sleep suspension, and bounded retries.
- Added tool-running and outputting protocol states, Codex tool-start/session-end hooks, connection-aware delivery, and exportable local recovery diagnostics.
- Preserved long-running task records and automatically removed active Codex and Claude Code records only after their owning process exited.
- Added trusted Codex Interrupt delivery and turn fencing so interrupted turns cannot be revived by late events or clear another active task.
- Renewed active Halo USB states before the firmware timeout while keeping NuPhy Bluetooth delivery change-driven.
- Kept Air60's amber double-pulse and green-breathing previews separate from Halo/AULA effects.
- Included Halo installer tests in firmware checks and checked every shell script in CI.
- Prevented spawned integration processes from retaining diagnostic and transmission file locks.
- Rewrote both READMEs with release-versus-source guidance, exact keyboard compatibility, lighting behavior, and outstanding physical verification.

These changes are not included in the published v0.5.9 assets. Air60 `stable-v7` firmware is unchanged.

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
