import Foundation
import Testing
@testable import AgentLightApp

@MainActor
private final class WakeRecoveryCounter {
    var value = 0
}

@MainActor
@Test("a workspace wake notification invokes the HID recovery handler once")
func workspaceWakeInvokesRecoveryHandler() {
    let center = NotificationCenter()
    let notification = Notification.Name("NuphyBar.Tests.didWake")
    let recoveryCount = WakeRecoveryCounter()
    let monitor = SystemWakeMonitor(center: center, notification: notification) {
        recoveryCount.value += 1
    }

    center.post(name: notification, object: nil)

    #expect(recoveryCount.value == 1)
    withExtendedLifetime(monitor) {}
}
