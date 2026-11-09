import Foundation
import Testing
@testable import AgentLightCore

private let historySession = "11111111-1111-4111-8111-111111111111"

private func historyLine(_ kind: String, turn: String? = nil, time: Double = 1_000,
                         envelope: String = "event_msg", session: String? = nil) throws -> String {
    var payload: [String: Any] = ["type": kind]
    if let turn { payload["turn_id"] = turn }
    if let session { payload["id"] = session }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let object: [String: Any] = ["type": envelope, "payload": payload,
        "timestamp": formatter.string(from: Date(timeIntervalSince1970: time))]
    return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n"
}

private struct HistoryFixture {
    let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let url: URL

    init(archived: Bool = false) throws {
        let folder = home.appending(path: archived ? "archived_sessions" : "sessions/2026/10/14")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appending(path: "rollout-test-\(historySession).jsonl")
    }

    func write(_ body: String, session: String = historySession) throws {
        let header = try historyLine("metadata", envelope: "session_meta", session: session)
        try Data((header + body).utf8).write(to: url)
    }

    func remove() { try? FileManager.default.removeItem(at: home) }
}

private func historyState(status: AgentSessionStatus = .working) -> AgentState {
    var state = AgentState()
    state.apply(.init(provider: .codex, sessionID: historySession, status: status,
        turnID: "A", lifecycle: .begin, occurredAt: 900), now: 900)
    return state
}

@Test("completed rollouts clean live shared owners without touching another working task",
      arguments: [AgentSessionStatus.working, .toolRunning, .outputting, .waiting])
func completedHistoryCleansOnlyItsTask(status: AgentSessionStatus) throws {
    let fixture = try HistoryFixture()
    defer { fixture.remove() }
    try fixture.write(historyLine("task_started", turn: "A", time: 900)
        + historyLine("task_complete", turn: "A", time: 1_000)
        + historyLine("task_started", turn: "B", time: 1_001)
        + historyLine("task_complete", turn: "B", time: 1_100))
    let history = CodexTurnHistory(home: fixture.home)
    var state = historyState(status: status)
    state.apply(.init(provider: .codex, sessionID: "another", status: .working), now: 1_200)
    #expect(state.reconcileCodexTurns(check: history.completion) == 1)
    #expect(state.sessions.count == 1)
    #expect(state.displayCommand(now: 90 * 24 * 3600) == .working)
    state.apply(.init(provider: .codex, sessionID: historySession, status: .working,
        turnID: "B", lifecycle: .begin, occurredAt: 1_001), now: 1_300)
    state.apply(.init(provider: .codex, sessionID: historySession, status: .working,
        turnID: "A", lifecycle: .activity, occurredAt: 1_400), now: 1_400)
    #expect(state.sessions.count == 1)
    state.apply(.init(provider: .codex, sessionID: historySession, status: .working,
        turnID: "C", lifecycle: .begin, occurredAt: 1_500), now: 1_500)
    #expect(state.sessions.count == 2)
}

@Test("an unfinished newer turn prevents cleanup of an older completed turn")
func newerLiveTurnBlocksCleanup() throws {
    let fixture = try HistoryFixture()
    defer { fixture.remove() }
    try fixture.write(historyLine("task_complete", turn: "A")
        + historyLine("task_started", turn: "B", time: 1_001))
    let history = CodexTurnHistory(home: fixture.home)
    var state = historyState()
    #expect(state.reconcileCodexTurns(check: history.completion) == 0)
    #expect(state.displayCommand(now: 90 * 24 * 3600) == .working)
}

@Test("quiet long tasks and absent evidence never expire")
func quietHistoryPreservesWork() throws {
    let fixture = try HistoryFixture()
    defer { fixture.remove() }
    try fixture.write(historyLine("task_started", turn: "A", time: 900))
    let history = CodexTurnHistory(home: fixture.home)
    var state = historyState()
    #expect(state.reconcileCodexTurns(check: history.completion) == 0)
    #expect(state.displayCommand(now: 90 * 24 * 3600) == .working)
    try FileManager.default.removeItem(at: fixture.url)
    #expect(state.reconcileCodexTurns(check: history.completion) == 0)
}

@Test("unknown lifecycle events, malformed lines, partial writes and wrong turns preserve work",
      arguments: ["unknown", "malformed", "partial", "wrong-turn", "overlap", "restarted", "old-end", "out-of-order", "missing-id"])
func ambiguousHistoryPreservesWork(mode: String) throws {
    let fixture = try HistoryFixture()
    defer { fixture.remove() }
    var body = try historyLine("task_complete", turn: "A")
    switch mode {
    case "unknown": body += try historyLine("task_resumed", turn: "A", time: 1_001)
    case "malformed": body += "{broken}\n"
    case "partial": body += "{\"type\":"
    case "wrong-turn": body = try historyLine("task_complete", turn: "other")
    case "overlap": body = try historyLine("task_started", turn: "other", time: 950) + body
    case "restarted": body += try historyLine("task_started", turn: "A", time: 1_001)
    case "old-end": body = try historyLine("task_complete", turn: "A", time: 800)
    case "out-of-order": body += try historyLine("task_started", turn: "B", time: 999)
    case "missing-id": body += try historyLine("turn_aborted", time: 1_001)
    default: break
    }
    try fixture.write(body)
    let history = CodexTurnHistory(home: fixture.home)
    var state = historyState()
    #expect(state.reconcileCodexTurns(check: history.completion) == 0)
    #expect(state.sessions.count == 1)
}

@Test("a wrong session header cannot clear a task")
func historyIdentityIsRequired() throws {
    let fixture = try HistoryFixture()
    defer { fixture.remove() }
    try fixture.write(historyLine("task_complete", turn: "A"), session: "wrong-session")
    #expect(CodexTurnHistory(home: fixture.home).completion(sessionID: historySession,
        turnID: "A", beganAt: 900) == nil)
}

@Test("assistant text and tool output cannot masquerade as a lifecycle ending")
func ordinaryOutputNeverEndsWork() throws {
    let fixture = try HistoryFixture()
    defer { fixture.remove() }
    try fixture.write(historyLine("task_started", turn: "A", time: 900)
        + historyLine("task_complete", turn: "A", envelope: "response_item"))
    #expect(CodexTurnHistory(home: fixture.home).completion(sessionID: historySession,
        turnID: "A", beganAt: 900) == nil)
}

@Test("duplicate rollout identities cannot establish completion")
func duplicateHistoryPreservesWork() throws {
    let fixture = try HistoryFixture()
    defer { fixture.remove() }
    try fixture.write(historyLine("task_complete", turn: "A"))
    let archive = fixture.home.appending(path: "archived_sessions")
    try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: fixture.url, to: archive.appending(path: fixture.url.lastPathComponent))
    #expect(CodexTurnHistory(home: fixture.home).completion(sessionID: historySession,
        turnID: "A", beganAt: 900) == nil)
}

@Test("bounded tails skip a huge body and require a complete matching terminal event")
func boundedHistoryTail() throws {
    let fixture = try HistoryFixture()
    defer { fixture.remove() }
    let large = "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"content\":\""
        + String(repeating: "x", count: 20_000) + "\"}}\n"
    try fixture.write(historyLine("task_started", turn: "A", time: 900)
        + large + historyLine("task_complete", turn: "A"))
    let history = CodexTurnHistory(home: fixture.home, tailLimit: 1024)
    #expect(history.completion(sessionID: historySession, turnID: "A", beganAt: 900) != nil)
    try fixture.write(historyLine("task_complete", turn: "A") + large)
    #expect(history.completion(sessionID: historySession, turnID: "A", beganAt: 900) == nil)
}

@Test("atomic history replacement and restart are rechecked rather than cached as ended")
func replacedHistoryIsRechecked() throws {
    let fixture = try HistoryFixture(archived: true)
    defer { fixture.remove() }
    try fixture.write(historyLine("task_complete", turn: "A"))
    let history = CodexTurnHistory(home: fixture.home)
    #expect(history.completion(sessionID: historySession, turnID: "A", beganAt: 900) != nil)
    let header = try historyLine("metadata", envelope: "session_meta", session: historySession)
    try Data((header + historyLine("task_started", turn: "A", time: 1_001)).utf8)
        .write(to: fixture.url, options: .atomic)
    #expect(history.completion(sessionID: historySession, turnID: "A", beganAt: 900) == nil)
}

@Test("automatic state loads persist terminal proof while the real owner stays alive")
func historyReconciliationIsDurable() throws {
    let fixture = try HistoryFixture()
    defer { fixture.remove() }
    try fixture.write(historyLine("task_complete", turn: "A"))
    let history = CodexTurnHistory(home: fixture.home)
    let file = AgentStateFile(url: fixture.home.appending(path: "state.json"), ownerStatus: { _ in .alive },
        turnEvidence: { history.completion(sessionID: $0, turnID: $1, beganAt: $2) })
    _ = try file.apply(.init(provider: .codex, sessionID: historySession, status: .working,
        turnID: "A", lifecycle: .begin,
        owner: AgentProcessOwner(pid: Int32(ProcessInfo.processInfo.processIdentifier), startedSeconds: 0,
            startedMicroseconds: 0), occurredAt: 900), now: 900)
    #expect(try file.load().sessions.isEmpty)
    _ = try file.apply(.init(provider: .codex, sessionID: historySession, status: .working,
        turnID: "A", lifecycle: .activity, occurredAt: 1_100), now: 1_100)
    #expect(try file.load().sessions.isEmpty)
}

@Test("replay a local state snapshot without changing the live state",
      .enabled(if: ProcessInfo.processInfo.environment["NUPHYBAR_REPLAY_STATE"] != nil))
func replayLocalStateSnapshot() throws {
    let environment = ProcessInfo.processInfo.environment
    let path = try #require(environment["NUPHYBAR_REPLAY_STATE"])
    let ended = try #require(environment["NUPHYBAR_ENDED_SESSION"])
    let live = try #require(environment["NUPHYBAR_LIVE_SESSION"])
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appending(path: "state.json")
    try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: url)
    let before = try JSONDecoder().decode(AgentState.self, from: Data(contentsOf: url))
    let provider = AgentProvider(rawValue: environment["NUPHYBAR_ENDED_PROVIDER"] ?? "codex")
    let endedKey = AgentSessionKey(provider: try #require(provider), sessionID: ended)
    let liveKey = AgentSessionKey(provider: .codex, sessionID: live)
    #expect(before.sessions[endedKey] != nil)
    #expect(before.sessions[liveKey] != nil)
    let file = AgentStateFile(url: url)
    var after = try file.load()
    for _ in 0..<512 where after.sessions[endedKey] != nil {
        after = try file.load()
    }
    #expect(after.sessions[endedKey] == nil)
    #expect(after.sessions[liveKey] == before.sessions[liveKey])
    #expect(after.sessions.count == before.sessions.count - 1)
}
