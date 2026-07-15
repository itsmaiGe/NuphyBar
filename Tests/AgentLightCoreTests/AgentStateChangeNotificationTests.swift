import Dispatch
import Testing
@testable import AgentLightCore

@Test("state change notifications wake a registered listener")
func stateChangeNotificationWakesListener() throws {
    let received = DispatchSemaphore(value: 0)
    let observation = try AgentStateChangeNotification.observe(
        on: DispatchQueue(label: "com.maige.NuphyBar.Tests.AgentStateNotification")
    ) {
        received.signal()
    }

    #expect(AgentStateChangeNotification.post())
    #expect(received.wait(timeout: .now() + 1) == .success)
    withExtendedLifetime(observation) {}
}
