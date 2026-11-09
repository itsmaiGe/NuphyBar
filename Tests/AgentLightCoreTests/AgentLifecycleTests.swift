import Darwin
import Foundation
import Testing
@testable import AgentLightCore

private let testOwner = AgentProcessOwner(pid: 42, startedSeconds: 100, startedMicroseconds: 123)

private func turn(_ id: String, _ lifecycle: AgentEventLifecycle, _ status: AgentSessionStatus,
                  at: Double = 1, session: String = "one") -> AgentEvent {
    AgentEvent(provider: .codex, sessionID: session, status: status, turnID: id,
        lifecycle: lifecycle, owner: testOwner, occurredAt: at)
}

@Test("Interrupt clears its turn without clearing another live task")
func interruptIsScoped() {
    var state = AgentState()
    state.apply(turn("A", .begin, .working), now: 1)
    state.apply(turn("B", .begin, .working, session: "two"), now: 1)
    state.apply(turn("A", .endTurn, .idle), now: 2)
    #expect(state.sessions.count == 1)
    #expect(state.displayCommand(now: 3) == .working)
    state.apply(turn("A", .activity, .working), now: 4)
    #expect(state.sessions.count == 1)
    state.apply(turn("B", .endTurn, .idle, session: "two"), now: 5)
    #expect(state.displayCommand(now: 5) == .idle)
}

@Test("old completions and delayed starts cannot end or replace a newer turn")
func oldEventsAreFenced() {
    var state = AgentState()
    state.apply(turn("A", .begin, .working, at: 10), now: 10)
    state.apply(turn("B", .begin, .toolRunning, at: 20), now: 20)
    state.apply(turn("A", .endTurn, .idle, at: 21), now: 21)
    state.apply(turn("A", .activity, .working, at: 22), now: 22)
    state.apply(turn("unseen-old", .begin, .working, at: 5), now: 23)
    #expect(state.displayCommand(now: 24) == .toolRunning)
    state.apply(turn("B", .endTurn, .complete, at: 25), now: 25)
    #expect(state.displayCommand(now: 50) == .idle)
    state.apply(turn("B", .activity, .working, at: 51), now: 51)
    #expect(state.displayCommand(now: 51) == .idle)
    state.apply(turn("C", .begin, .working, at: 60), now: 60)
    #expect(state.displayCommand(now: 60) == .working)
}

@Test("a stale session-end cannot clear a newly started turn")
func delayedSessionEnd() {
    var state = AgentState()
    state.apply(turn("new", .begin, .working, at: 20), now: 20)
    state.apply(AgentEvent(provider: .codex, sessionID: "one", status: .idle,
        lifecycle: .endSession, occurredAt: 10), now: 30)
    #expect(state.displayCommand(now: 30) == .working)
}

@Test("a fresh explicit continuation can resume a completed turn, but delayed activity cannot")
func explicitStopContinuation() {
    var state = AgentState()
    state.apply(turn("A", .begin, .working, at: 10), now: 10)
    state.apply(turn("A", .endTurn, .complete, at: 20), now: 20)
    state.apply(turn("A", .activity, .working, at: 21), now: 21)
    #expect(state.displayCommand(now: 21) == .complete)
    state.apply(turn("A", .begin, .working, at: 15), now: 22)
    #expect(state.displayCommand(now: 22) == .complete)
    state.apply(turn("A", .begin, .working, at: 30), now: 30)
    #expect(state.displayCommand(now: 100_000) == .working)
}

@Test("owner exit preserves the existing short completion and error indications")
func terminalLightsAreUnchanged() {
    for status in [AgentSessionStatus.complete, .error] {
        var state = AgentState()
        state.apply(turn("A", .begin, .working), now: 1)
        state.apply(turn("A", .endTurn, status), now: 2)
        #expect(state.reconcileOwners(check: { _ in .exited }) == 0)
        #expect(state.displayCommand(now: 3) == (status == .complete ? .complete : .error))
        #expect(state.displayCommand(now: 18) == .idle)
    }
}

@Test("live and unverifiable owners never expire after silence or days of work")
func longTasksAndUnknownOwnersSurvive() {
    var state = AgentState()
    state.apply(turn("long", .begin, .working), now: 1)
    state.apply(.init(provider: .codex, sessionID: "legacy", status: .working), now: 1)
    #expect(state.reconcileOwners(check: { _ in .alive }) == 0)
    #expect(state.displayCommand(now: 90 * 24 * 3600) == .working)
    #expect(state.reconcileOwners(check: { _ in .unknown }) == 0)
    #expect(state.sessions.count == 2)
    #expect(state.reconcileOwners(check: { _ in .exited }) == 1)
    #expect(state.sessions.count == 1)
}

@Test("process restart or PID reuse does not keep an old owner alive")
func processIdentityIncludesStartTime() {
    let reused = AgentProcessOwner(pid: getpid(), startedSeconds: 0, startedMicroseconds: 0)
    #expect(reused.status() == .exited)
    #expect(AgentProcessOwner(pid: -1, startedSeconds: 0, startedMicroseconds: 0).status() == .unknown)
}

@Test("a new turn with unknown ownership never inherits an exited prior owner")
func newOwnerMustBeObserved() {
    var state = AgentState()
    state.apply(turn("A", .begin, .working, at: 1), now: 1)
    state.apply(.init(provider: .codex, sessionID: "one", status: .working,
        turnID: "B", lifecycle: .begin, occurredAt: 2), now: 2)
    #expect(state.reconcileOwners(check: { _ in .exited }) == 0)
    #expect(state.displayCommand(now: 1_000_000) == .working)
}

@Test("startup state reading cleans exited owners atomically and persists turn fencing")
func durableOwnerReconciliation() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "state.json")
    let writer = AgentStateFile(url: url, ownerStatus: { _ in .alive })
    _ = try writer.apply(turn("A", .begin, .working), now: 1)
    let reader = AgentStateFile(url: url, ownerStatus: { _ in .exited })
    #expect(try reader.load().sessions.isEmpty)
    _ = try writer.apply(turn("A", .activity, .working), now: 100)
    #expect(try writer.load().sessions.isEmpty)
    _ = try writer.apply(turn("B", .begin, .working, at: 101), now: 101)
    #expect(try writer.load().sessions.count == 1)
}

@Test("legacy state migrates without deleting active work")
func oldStateIsPreserved() throws {
    let old = AgentState(sessions: [.init(provider: .codex, sessionID: "old"):
        AgentSessionRecord(status: .working, updatedAt: 1)])
    let data = try JSONEncoder().encode(old)
    let parsed = try JSONSerialization.jsonObject(with: data)
    var object = try #require(parsed as? [String: Any])
    object.removeValue(forKey: "codexTurns")
    var decoded = try JSONDecoder().decode(AgentState.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(decoded.reconcileOwners(check: { _ in .exited }) == 0)
    #expect(decoded.displayCommand(now: 10_000_000) == .working)
}

@Test("Interrupt is an advisory idle event with no response that could restart work")
func interruptHookContract() throws {
    let payload = Data(#"{"session_id":"one","turn_id":"A"}"#.utf8)
    let mapped = try HookEventMapper.map(provider: .codex, eventName: "Interrupt", payload: payload)
    let event = try #require(mapped)
    #expect(event.status == .idle)
    #expect(event.lifecycle == .endTurn)
    #expect(HookEventMapper.response(provider: .codex, eventName: "Interrupt") == nil)
}

@Test("an actual owner exit is cleaned while another live owner is preserved")
func realProcessExit() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["30"]
    try process.run()
    defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
    var info = proc_bsdinfo()
    #expect(proc_pidinfo(process.processIdentifier, PROC_PIDTBSDINFO, 0, &info,
        Int32(MemoryLayout<proc_bsdinfo>.size)) == Int32(MemoryLayout<proc_bsdinfo>.size))
    let owner = AgentProcessOwner(pid: process.processIdentifier,
        startedSeconds: info.pbi_start_tvsec, startedMicroseconds: info.pbi_start_tvusec)
    #expect(owner.status() == .alive)
    var selfInfo = proc_bsdinfo()
    _ = proc_pidinfo(getpid(), PROC_PIDTBSDINFO, 0, &selfInfo, Int32(MemoryLayout<proc_bsdinfo>.size))
    let live = AgentProcessOwner(pid: getpid(), startedSeconds: selfInfo.pbi_start_tvsec,
        startedMicroseconds: selfInfo.pbi_start_tvusec)
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = AgentStateFile(url: folder.appending(path: "state.json"))
    _ = try file.apply(.init(provider: .codex, sessionID: "exiting", status: .working,
        owner: owner), now: 1)
    _ = try file.apply(.init(provider: .codex, sessionID: "live", status: .working,
        owner: live), now: 1)
    #expect(try file.load().sessions.count == 2)
    process.terminate()
    process.waitUntilExit()
    #expect(owner.status() == .exited)
    let state = try file.load()
    #expect(state.sessions.count == 1)
    #expect(state.sessions.keys.first?.sessionID == "live")
}
