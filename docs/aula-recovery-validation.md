# AULA recovery candidate 0.5.13, build 29

The AULA F99 Pro integration supports Bluetooth Low Energy, identified as `AULA-F99Pro 5.0`. The 2.4 GHz receiver does not have a lighting implementation.

## Observed failure

On 2026-09-05, Bluetooth writes returned `kIOReturnNotPermitted` while the public `IsSecureEventInputEnabled()` API returned true. Restarting the keyboard and app did not resolve the refusal. Later, the API returned false, the app resumed successful one-second working reports, and the user confirmed the red light. The registry initially attributed secure input to WeChat and later to loginwindow; these identifiers alone do not establish which component caused the restriction to persist.

## Implementation

- AULA delivery uses a separate controller. NuPhy command encoding, delivery reduction, reconnect policy, and firmware remain unchanged.
- Secure input, screen sleep, and system sleep pause AULA writes while preserving task records. The one-second scheduler checks for security release; power notifications update the sleep gate immediately. System wake alone does not clear a sleeping screen.
- Resuming or reconnecting sends the latest state. Completion during suspension returns to idle. Idle restores the factory effect once and stops color refreshes.
- A queued send checks the gate again before admission. An already admitted system call may finish during suspension; its result cannot acknowledge a newer target or connection.
- AULA permission refusals preserve the HID connection instead of repeatedly rebuilding it. If secure input is not reported, a refusal retries at most once per thirty seconds and displays a separate access message. Ordinary transport failures retain the existing recovery behavior.
- Successful unchanged AULA writes are logged at most once per minute. State and connection changes are logged immediately. NuPhy success logging is unchanged.

## Automated validation

Tests cover secure input and sleep gates, latest-state restoration, queued-write cancellation before admission, stale in-flight completion, one concurrent sender, permission retry limits, screen sleep across background wake, and 28,800 simulated one-second refreshes followed by idle. A profile comparison verifies that only AULA skips manager cancellation on a permission refusal.

Simulated eight-hour coverage validates scheduling and task duration, not Bluetooth battery life or physical overnight stability.

On 2026-09-05, all 102 tests passed in two consecutive full runs after replacing fixed-yield test waits with completion-based waits. The release build and strict signature verification passed. The prior 0.5.12 application and a state snapshot were backed up before installing 0.5.13 build 29.

## Installed candidate evidence

At 16:00:31 UTC, a test process enabled its own secure-input request for eight seconds. The installed app recorded `aula.pause.changed: secureInput`. At 16:00:39 UTC, the test released its own request, the app recorded `resumed`, and the current working command was accepted on the same connection. No HID failure or manager rebuild occurred during the interval. A subsequent public API check confirmed secure input was disabled.

The test did not disable another process's security request or modify system security settings. Physical LED appearance during this controlled interval was not independently observed.

## Hardware acceptance

On 2026-09-09, the user reported that both the NuPhy and AULA keyboards were working normally in their testing and approved submitting the changes for review. This is real-world validation; exact endurance durations and cycle counts were not reported.

- Confirm red while working and factory lighting after the final task completes.
- Temporarily enable secure input in a test process and release only that process's own request. Verify a pause event, no repeated manager rebuilds, and automatic current-state delivery after release.
- Power-cycle the keyboard ten times on the same Bluetooth slot and confirm current-state replay without restarting the app.
- Test screen sleep and system sleep separately, including task completion while the display is asleep.
- Let the keyboard sleep naturally while the Mac remains awake. Determine whether real-time RGB refresh delays keyboard sleep and verify state recovery after typing.
- Compare unexpected wake behavior with the app closed, idle, and displaying work. Attribute wake events from system logs; a generic Bluetooth wake does not identify the keyboard or prove that app writes caused it.
- Run two hours of physical continuous work and an overnight session before claiming hardware endurance.

The specific controlled cycle counts and endurance durations above have not been independently recorded. No system security settings are disabled by the implementation.

## Remaining task-lifecycle limitation

A stale working record from an interrupted Codex task was identified and individually cleared on 2026-09-05 after verifying that task's interrupted status. This release does not add automatic interrupted-task reconciliation. Its AULA connection and suspension fixes do not address missing task termination events.
