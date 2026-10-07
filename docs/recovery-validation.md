# Recovery candidate 0.5.12, build 28

This candidate repairs connection recovery and removes sleep-driven task deletion. It has been validated on a Halo75 V2 through a Bluetooth power cycle, automatic reconnection without restarting the app, normal state transitions, and cross-day wake and use.

## Implemented

- Device handles, profiles, and connection identities are selected and cleared together. Rebuilding can rediscover the same keyboard. Refresh also drops devices absent from enumeration when a removal callback was missed.
- Discovery and delivery share one HID owner. Every app send carries a connection identity, and stale send results cannot update a replacement connection.
- Only actual system wake requests a rebuild. Screen sleep and session locking never delete task records. Repeated wake requests coalesce during cancellation.
- Manager cancellation has a visible ten-second watchdog. A delayed cancellation callback can still resume recovery. No second manager is opened while cancellation is pending.
- Reconnection sends the latest persisted state. Notifications and the five-second fallback reader share one delivery reducer. The fallback compares content, so unchanged file timestamps cannot hide an update.
- Active tasks retain unlimited duration. AULA keepalive and each supported device's report protocol remain separate.
- Invalid task files are preserved and reported. Hook parsing and persistence errors no longer exit successfully without explanation.
- A bounded local diagnostic journal records hook receipt, anonymized session and turn identifiers, state reads, connection transitions, and writes accepted by macOS. Export is available in Keyboard settings. Diagnostic lock contention drops that diagnostic write instead of blocking a hook or HID recovery.
- Codex `SessionEnd` uses the documented three-second maximum. Its changed hook definition requires renewed trust when the integration is updated. `Stop` still returns the required empty JSON object. See the [official Hooks documentation](https://learn.chatgpt.com/docs/hooks).

## Automated evidence

The new injectable backend runs the production transport state machine. With the original rebuild logic preserved, `rebuildSameDeviceThenSend` remained in `rebuilding` and failed to send; `obsoleteManagerCallbacks` also failed. The fixes make both tests pass.

On 2026-09-02:

- `swift test`: 95 tests passed.
- Coverage includes twenty simulated rebuild cycles, keyboard-only disconnect, absent-at-start discovery, stalled cancellation, missed removal callbacks, stale delivery tokens, USB-to-Bluetooth fallback, and all four device profiles.
- App-level tests read a temporary real state file and verify offline completion is delivered as idle, plus content updates with unchanged modification time.
- `firmware/halo75-v2-ansi/test.sh`: effect model tests passed.
- `firmware/air60-v2/test.sh`: effect model tests and three candidate-builder tests passed.
- Release app built and passed strict signature verification.
- Thread Sanitizer could not execute. A narrowed retry failed before test discovery because macOS rejected the sanitizer library with `Sanitizer load violates platform policy`. This is not a passing concurrency audit. Security policy was not changed.

## Physical evidence

On 2026-09-02 and 2026-09-03, the installed 0.5.12 build 28 candidate was exercised on the target Halo75 V2 over Bluetooth:

- Waiting, working, completion, and idle transitions displayed the expected keyboard effects.
- Turning the keyboard off for ten seconds and reconnecting it to the same Bluetooth slot restored the current effect without restarting the app.
- The keyboard and app recovered normally during cross-day wake and use.
- A transient failed HID report was followed by disconnect, rediscovery, and an accepted current-state write in about 0.23 seconds.

## Remaining work

- Task records still use the existing `state-v2.json` schema. Turn identity is captured for diagnostics, not yet used as an ordering or cancellation authority. Persistent revision migration, stale-turn fencing, and reliable interruption reconciliation remain pending.
- Obtain local event samples for manual stop, approval cancellation, normal app exit, abnormal exit, and Stop-triggered continuation before changing task termination behavior. `SessionEnd` is a session event, not a universal per-turn cancellation event. No transcript parser or process-liveness inference was added.
- Formal endurance runs of twenty physical reconnect cycles and ten controlled system sleep and wake cycles have not been performed. Automated coverage contains twenty simulated rebuild cycles.
- This historical candidate did not renew USB states before the firmware's separate fifteen-minute timeout. Current source fixes this on the host by renewing active Halo USB states every five minutes; Bluetooth remains change-driven, and firmware is unchanged.

## Deployment status

Version 0.5.12 build 28 is installed and physically validated on the target Halo75 V2. The prior app and hook configuration remain backed up. Updating the Codex integration changes the SessionEnd hook hash; review that hook through Codex rather than editing trust hashes manually. Preserve the existing state file.

The remaining controlled endurance checks and task-lifecycle research are documented limitations, not claims of completed validation.
