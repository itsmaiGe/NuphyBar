import Foundation
import Testing
@testable import AgentLightCore

@Test("state persists across short-lived hook helper processes")
func statePersistsAcrossInstances() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let url = directory.appending(path: "state.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let first = AgentStateFile(url: url)
    #expect(try first.apply(.init(provider: .codex, sessionID: "one", status: .working), now: 100)
            == .working)

    let second = AgentStateFile(url: url)
    #expect(try second.apply(.init(provider: .claudeCode, sessionID: "two", status: .complete), now: 101)
            == .working)

    let snapshot = try second.load()
    #expect(snapshot.sessions.count == 2)
}

@Test("a missing state file starts empty")
func missingStateStartsEmpty() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }

    let file = AgentStateFile(url: directory.appending(path: "state.json"))
    #expect(try file.load() == AgentState())
}
