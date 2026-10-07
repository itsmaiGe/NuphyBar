import AppKit
import Testing
@testable import AgentLightApp

@MainActor
private final class WakeCounter { var count = 0 }

@MainActor
@Test("screen sleep and lock do not trigger recovery or mutate agent state")
func screenSleepAndLockAreIgnored() {
    let center = NotificationCenter()
    let counter = WakeCounter()
    let monitor = SystemLifecycleMonitor(center: center, resumeHandler: { counter.count += 1 })
    for notification in [NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification,
                         NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification,
                         NSWorkspace.willSleepNotification] {
        center.post(name: notification, object: nil)
    }
    #expect(counter.count == 0)
    center.post(name: NSWorkspace.didWakeNotification, object: nil)
    #expect(counter.count == 1)
    withExtendedLifetime(monitor) {}
}
