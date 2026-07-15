import Dispatch
import Foundation
import Testing
@testable import AgentLightCore

@Test("recording an Agent event persists it before waking listeners")
func recordingAgentEventPersistsBeforeNotification() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = AgentStateFile(url: directory.appending(path: "state.json"))
    let key = AgentSessionKey(provider: .codex, sessionID: "notification-test")
    let received = DispatchSemaphore(value: 0)
    let observation = try AgentStateChangeNotification.observe(
        on: DispatchQueue(label: "com.maige.NuphyBar.Tests.AgentStateNotification")
    ) {
        if (try? file.load().sessions[key]?.status) == .working {
            received.signal()
        }
    }

    _ = try file.record(
        .init(provider: .codex, sessionID: "notification-test", status: .working),
        now: 100
    )
    #expect(received.wait(timeout: .now() + 1) == .success)
    withExtendedLifetime(observation) {}
}
