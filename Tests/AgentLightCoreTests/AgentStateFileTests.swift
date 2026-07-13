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
            == nil)

    let snapshot = try second.load()
    #expect(snapshot.sessions.count == 2)
}

@Test("repeated lifecycle events are coalesced instead of resending BLE frames")
func repeatedEventsAreCoalesced() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = AgentStateFile(url: directory.appending(path: "state.json"))

    #expect(try file.apply(.init(provider: .codex, sessionID: "one", status: .working), now: 100)
            == .working)
    #expect(try file.apply(.init(provider: .codex, sessionID: "one", status: .working), now: 101)
            == nil)
}

@Test("a missing state file starts empty")
func missingStateStartsEmpty() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }

    let file = AgentStateFile(url: directory.appending(path: "state.json"))
    #expect(try file.load() == AgentState())
}

@Test("a damaged transient state file repairs itself on the next event")
func damagedStateRepairsOnNextEvent() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let url = directory.appending(path: "state.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("not-json".utf8).write(to: url)

    let file = AgentStateFile(url: url)
    #expect(try file.apply(.init(provider: .codex, sessionID: "one", status: .working), now: 100)
            == .working)
    #expect(try file.load().sessions.count == 1)
}
