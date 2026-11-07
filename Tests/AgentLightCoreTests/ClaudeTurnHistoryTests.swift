import Foundation
import Testing
@testable import AgentLightCore

private let claudeSession = "22222222-2222-4222-8222-222222222222"

private func claudeLine(_ type: String, time: Double = 900, id: String = "prompt", parent: String? = nil,
    reason: String? = nil, error: Bool = false, session: String = claudeSession,
    blocks: [[String: Any]]? = nil, extra: [String: Any] = [:]) throws -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var entry: [String: Any] = ["type": type, "timestamp": formatter.string(from: Date(timeIntervalSince1970: time)),
        "uuid": id, "sessionId": session]
    if let parent { entry["parentUuid"] = parent }
    if type == "user" || type == "assistant" {
        var message: [String: Any] = ["role": type, "content": blocks ?? [["type": "text", "text": "private fixture text"]]]
        if let reason { message["stop_reason"] = reason }
        entry["message"] = message
    }
    if error { entry["isApiErrorMessage"] = true }
    for (key, value) in extra { entry[key] = value }
    return String(decoding: try JSONSerialization.data(withJSONObject: entry), as: UTF8.self) + "\n"
}

private struct ClaudeFixture {
    let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let url: URL
    let history: ClaudeTurnHistory
    init() throws {
        let project = home.appending(path: "projects/work")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        url = project.appending(path: "\(claudeSession).jsonl")
        history = ClaudeTurnHistory(home: home)
    }
    func write(_ body: String) throws { try Data(body.utf8).write(to: url, options: .atomic) }
    func proof(_ threshold: Double = 900) -> ClaudeTurnEvidence? {
        history.completion(sessionID: claudeSession, transcriptPath: nil, notBefore: threshold)
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}

private func claudeEnding(error: Bool = true) throws -> String {
    try claudeLine("user") + claudeLine("api-request", time: 901)
        + claudeLine("assistant", time: 1_000, id: "end", parent: "prompt",
            reason: error ? "stop_sequence" : "end_turn", error: error)
}

@Test("Claude transcript-only queue notifications preserve a proven ending")
func claudeTranscriptOnlyQueueNotification() throws {
    let fixture = try ClaudeFixture()
    defer { fixture.remove() }
    let completed = try claudeEnding(error: false)
        + claudeLine("system", time: 1_001, id: "summary", parent: "end", extra: ["subtype": "stop_hook_summary"])
    let dequeue = try claudeLine("queue-operation", time: 1_002, extra: ["operation": "dequeue"])
    let metadata: [String: Any] = [
        "origin": ["kind": "task-notification"], "promptSource": "system",
        "queueTranscriptOnly": true, "isSidechain": false,
    ]
    let notification = try claudeLine("user", time: 1_003, id: "notification", parent: "summary", extra: metadata)
    try fixture.write(completed + dequeue + notification)
    #expect(fixture.proof()?.endedAt == 1_000)
    #expect(fixture.proof(1_001) == nil)
    try fixture.write(completed + dequeue)
    #expect(fixture.proof() == nil)
    for extra in [[:], metadata.merging(["queueTranscriptOnly": false], uniquingKeysWith: { _, new in new })] {
        try fixture.write(completed + dequeue + claudeLine("user", time: 1_003, parent: "summary", extra: extra))
        #expect(fixture.proof() == nil)
    }
    try fixture.write(completed + dequeue + claudeLine("user", time: 1_003, parent: "unrelated", extra: metadata))
    #expect(fixture.proof() == nil)
    try fixture.write(completed + dequeue + notification + claudeLine("api-request", time: 1_004))
    #expect(fixture.proof() == nil)
}

private func claudeLongTurn() throws -> String {
    var body = try claudeLine("user")
    var parent = "prompt"
    for step in 0..<40 {
        let tool = "tool-\(step)"
        let result = "result-\(step)"
        let attachment = "attachment-\(step)"
        body += try claudeLine("assistant", time: 901 + Double(step * 2), id: tool, parent: parent,
            reason: "tool_use", blocks: [["type": "tool_use", "id": tool]])
        body += try claudeLine("user", time: 902 + Double(step * 2), id: result, parent: tool,
            blocks: [["type": "tool_result", "tool_use_id": tool]])
        body += try claudeLine("attachment", time: 902 + Double(step * 2), id: attachment, parent: result)
        parent = attachment
    }
    return body
}

private func claudeDrain(_ history: ClaudeTurnHistory, threshold: Double = 900) -> ClaudeTurnEvidence? {
    for _ in 0..<256 {
        if let proof = history.completion(sessionID: claudeSession, transcriptPath: nil, notBefore: threshold) {
            return proof
        }
    }
    return nil
}

@Test("Claude long turns recover their anchor across bounded pages and restart", arguments: [false, true])
func claudeProgressiveRecovery(error: Bool) throws {
    let fixture = try ClaudeFixture()
    defer { fixture.remove() }
    let body = try claudeLongTurn() + claudeLine("assistant", time: 1_000, id: "end", parent: "attachment-39",
        reason: error ? "stop_sequence" : "end_turn", error: error)
    try fixture.write(body)
    let history = ClaudeTurnHistory(home: fixture.home, tailLimit: 1024)
    #expect(history.completion(sessionID: claudeSession, transcriptPath: nil, notBefore: 900) == nil)
    let proof = try #require(claudeDrain(history))
    #expect(proof.status == (error ? .error : .complete))
    #expect(proof.endedAt == 1_000)
    #expect(claudeDrain(history, threshold: 1_001) == nil)
    #expect(claudeDrain(ClaudeTurnHistory(home: fixture.home, tailLimit: 1024))?.endedAt == 1_000)
}

@Test("Claude paged scans never finish active or incomplete long turns",
    arguments: ["active", "pending-tool", "new-request", "new-prompt", "unknown", "partial", "oversized"])
func claudeProgressiveActiveWork(mode: String) throws {
    let fixture = try ClaudeFixture()
    defer { fixture.remove() }
    var body = try claudeLongTurn()
    if mode == "pending-tool" {
        body += try claudeLine("assistant", time: 990, id: "pending", parent: "attachment-39",
            reason: "tool_use", blocks: [["type": "tool_use", "id": "pending-tool"]])
    }
    if mode != "active" {
        body += try claudeLine("assistant", time: 1_000, id: "end",
            parent: mode == "pending-tool" ? "pending" : "attachment-39", reason: "end_turn")
    }
    switch mode {
    case "new-request": body += try claudeLine("api-request", time: 1_001)
    case "new-prompt": body += try claudeLine("user", time: 1_001, id: "next")
    case "unknown": body += try claudeLine("unrecognized-lifecycle", time: 1_001)
    case "partial": body += "{\"type\":"
    case "oversized": body += try claudeLine("attachment", time: 1_001, id: "large", parent: "end",
        extra: ["opaque": String(repeating: "x", count: 8_000)])
    default: break
    }
    try fixture.write(body)
    #expect(claudeDrain(ClaudeTurnHistory(home: fixture.home, tailLimit: 1024)) == nil)
}

@Test("Claude API retries extend the root chain without ending work", arguments: [false, true])
func claudeProgressiveRetryChain(ended: Bool) throws {
    let fixture = try ClaudeFixture()
    defer { fixture.remove() }
    var body = try claudeLongTurn()
        + claudeLine("system", time: 990, id: "notice", parent: "attachment-39", extra: ["subtype": "informational"])
        + claudeLine("system", time: 991, id: "retry-1", parent: "notice", extra: ["subtype": "api_error"])
        + claudeLine("system", time: 992, id: "retry-2", parent: "retry-1", extra: ["subtype": "api_error"])
    if ended {
        body += try claudeLine("assistant", time: 1_000, parent: "retry-2", reason: "end_turn")
    }
    try fixture.write(body)
    let proof = claudeDrain(ClaudeTurnHistory(home: fixture.home, tailLimit: 1024))
    #expect(proof?.status == (ended ? .complete : nil))
    try fixture.write(claudeEnding(error: false)
        + claudeLine("system", time: 1_001, id: "retry-after", parent: "end", extra: ["subtype": "api_error"]))
    #expect(claudeDrain(ClaudeTurnHistory(home: fixture.home, tailLimit: 1024)) == nil)
}

@Test("replay a large local Claude transcript through bounded scanning",
    .enabled(if: ProcessInfo.processInfo.environment["NUPHYBAR_REPLAY_CLAUDE_TRANSCRIPT"] != nil))
func replayLocalClaudeTranscript() throws {
    let environment = ProcessInfo.processInfo.environment
    let path = try #require(environment["NUPHYBAR_REPLAY_CLAUDE_TRANSCRIPT"])
    let session = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    let bytes = try #require(UInt64(environment["NUPHYBAR_REPLAY_CLAUDE_BYTES"] ?? ""))
    let expectedEnd = try #require(Double(environment["NUPHYBAR_REPLAY_CLAUDE_END"] ?? ""))
    let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let project = home.appending(path: "projects/replay")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let destination = project.appending(path: "\(session).jsonl")
    FileManager.default.createFile(atPath: destination.path, contents: nil)
    let input = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    let output = try FileHandle(forWritingTo: destination)
    defer { try? input.close(); try? output.close() }
    var remaining = bytes
    while remaining > 0 {
        let read = try input.read(upToCount: Int(min(remaining, 2 * 1024 * 1024)))
        let chunk = try #require(read)
        try #require(!chunk.isEmpty)
        try output.write(contentsOf: chunk)
        remaining -= UInt64(chunk.count)
    }
    let history = ClaudeTurnHistory(home: home)
    var proof: ClaudeTurnEvidence?
    for _ in 0..<512 where proof == nil {
        proof = history.completion(sessionID: session, transcriptPath: nil, notBefore: expectedEnd - 60)
    }
    #expect(proof?.status == .complete)
    #expect(proof?.endedAt == expectedEnd)
}

@Test("Claude scanning discards partial evidence after append, replacement or truncation",
    arguments: ["append", "replace", "truncate", "rewrite"])
func claudeProgressiveSnapshotChanges(mode: String) throws {
    let fixture = try ClaudeFixture()
    defer { fixture.remove() }
    let body = try claudeLongTurn() + claudeLine("assistant", time: 1_000, parent: "attachment-39", reason: "end_turn")
    try fixture.write(body)
    let history = ClaudeTurnHistory(home: fixture.home, tailLimit: 1024)
    for _ in 0..<5 {
        #expect(history.completion(sessionID: claudeSession, transcriptPath: nil, notBefore: 900) == nil)
    }
    switch mode {
    case "append":
        let handle = try FileHandle(forWritingTo: fixture.url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(claudeLine("api-request", time: 1_001).utf8))
        try handle.close()
    case "rewrite":
        try Data((body + claudeLine("api-request", time: 1_001)).utf8).write(to: fixture.url)
    case "replace":
        try fixture.write(claudeLongTurn() + claudeLine("api-request", time: 1_001))
    default:
        try fixture.write(claudeLine("user", time: 1_001, id: "new"))
    }
    #expect(claudeDrain(history) == nil)
}

@Test("Claude cached completion is invalidated immediately when the file gains a new request")
func claudeProgressiveCacheInvalidation() throws {
    let fixture = try ClaudeFixture()
    defer { fixture.remove() }
    let body = try claudeLongTurn() + claudeLine("assistant", time: 1_000, parent: "attachment-39", reason: "end_turn")
    try fixture.write(body)
    let history = ClaudeTurnHistory(home: fixture.home, tailLimit: 1024)
    #expect(claudeDrain(history)?.endedAt == 1_000)
    let handle = try FileHandle(forWritingTo: fixture.url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(claudeLine("api-request", time: 1_001).utf8))
    try handle.close()
    #expect(history.completion(sessionID: claudeSession, transcriptPath: nil, notBefore: 900) == nil)
    #expect(claudeDrain(history) == nil)
}

@Test("Claude state reconciliation finishes a paged scan with a live owner and preserves newer work")
func claudeProgressiveStateReconciliation() throws {
    let fixture = try ClaudeFixture()
    defer { fixture.remove() }
    try fixture.write(claudeLongTurn()
        + claudeLine("assistant", time: 1_000, parent: "attachment-39", reason: "end_turn"))
    let history = ClaudeTurnHistory(home: fixture.home, tailLimit: 1024)
    let file = AgentStateFile(url: fixture.home.appending(path: "state.json"), ownerStatus: { _ in .alive },
        claudeEvidence: { session, path, threshold in
            guard session == claudeSession else { return nil }
            return history.completion(sessionID: session, transcriptPath: path, notBefore: threshold)
        })
    let owner = AgentProcessOwner(pid: 42, startedSeconds: 1, startedMicroseconds: 0)
    let live = UUID().uuidString
    let key = AgentSessionKey(provider: .claudeCode, sessionID: claudeSession)
    let liveKey = AgentSessionKey(provider: .claudeCode, sessionID: live)
    _ = try file.apply(.init(provider: .claudeCode, sessionID: claudeSession, status: .working,
        lifecycle: .begin, owner: owner, occurredAt: 900, transcriptPath: fixture.url.path), now: 900)
    _ = try file.apply(.init(provider: .claudeCode, sessionID: live, status: .working,
        lifecycle: .begin, owner: owner, occurredAt: 1_100), now: 1_100)
    var state = try file.load()
    let liveRecord = try #require(state.sessions[liveKey])
    #expect(state.sessions[key]?.status == .working)
    for _ in 0..<256 where state.sessions[key] != nil { state = try file.load() }
    #expect(state.sessions[key] == nil)
    #expect(state.sessions[liveKey] == liveRecord)
    _ = try file.apply(.init(provider: .claudeCode, sessionID: claudeSession, status: .working,
        lifecycle: .activity, owner: owner, occurredAt: 1_100), now: 1_100)
    #expect(try file.load().sessions[key] == nil)
    _ = try file.apply(.init(provider: .claudeCode, sessionID: claudeSession, status: .working,
        lifecycle: .begin, owner: owner, occurredAt: 1_200), now: 1_200)
    #expect(try file.load().sessions[key]?.status == .working)
}

@Test("Claude normal completion and API failure are explicit terminal evidence", arguments: [false, true])
func claudeTerminalEvidence(error: Bool) throws {
    let fixture = try ClaudeFixture()
    defer { fixture.remove() }
    try fixture.write(claudeEnding(error: error))
    let proof = try #require(fixture.proof())
    #expect(proof.status == (error ? .error : .complete))
    #expect(proof.endedAt == 1_000)
    #expect(fixture.proof(1_001) == nil)
}

@Test("Claude attachment and hook metadata preserve the native parent chain")
func claudeNativeAttachmentChain() throws {
    let fixture = try ClaudeFixture()
    defer { fixture.remove() }
    try fixture.write(claudeLine("user")
        + claudeLine("system", time: 901, id: "hook", parent: "prompt", extra: ["subtype": "hook_progress"])
        + claudeLine("attachment", time: 902, id: "attached", parent: "hook")
        + claudeLine("api-request-shape", time: 903)
        + claudeLine("api-request-blob", time: 903)
        + claudeLine("api-request", time: 904)
        + claudeLine("assistant", time: 1_000, id: "end", parent: "attached", reason: "stop_sequence", error: true))
    #expect(fixture.proof()?.status == .error)
}

@Test("Claude response metadata may be timestamped after its attached terminal response", arguments: [false, true])
func claudeAttachmentTimestampOrdering(error: Bool) throws {
    let fixture = try ClaudeFixture()
    defer { fixture.remove() }
    let body = try claudeLine("user") + claudeLine("api-request", time: 901)
        + claudeLine("attachment", time: 1_000.001, id: "attached", parent: "prompt")
        + claudeLine("assistant", time: 1_000, id: "end", parent: "attached",
            reason: error ? "stop_sequence" : "end_turn", error: error)
        + claudeLine("system", time: 1_000.084, id: "summary", parent: "end", extra: ["subtype": "stop_hook_summary"])
    try fixture.write(body)
    let proof = try #require(fixture.proof())
    #expect(proof.status == (error ? .error : .complete))
    #expect(proof.endedAt == 1_000)
    #expect(fixture.proof(1_000.0005) == nil)
    for next in [try claudeLine("user", time: 1_001, id: "next"),
                 try claudeLine("api-request", time: 1_001),
                 try claudeLine("attachment", time: 1_001, id: "later", parent: "end")] {
        try fixture.write(body + next)
        #expect(fixture.proof() == nil)
    }
    try fixture.write(claudeLine("user")
        + claudeLine("attachment", time: 1_000.001, id: "unrelated", parent: "foreign")
        + claudeLine("assistant", time: 1_000, parent: "unrelated", reason: "end_turn"))
    #expect(fixture.proof() == nil)
}

@Test("Claude tool failure is not task failure and pending tools block completion")
func claudeToolFailuresKeepWork() throws {
    let fixture = try ClaudeFixture()
    defer { fixture.remove() }
    let invoking = try claudeLine("user") + claudeLine("assistant", time: 901, id: "tool", parent: "prompt",
        reason: "tool_use", blocks: [["type": "tool_use", "id": "tool-1"]])
    try fixture.write(invoking)
    #expect(fixture.proof() == nil)
    let result = try claudeLine("user", time: 902, id: "result", parent: "tool",
        blocks: [["type": "tool_result", "tool_use_id": "tool-1", "is_error": true]])
    try fixture.write(invoking + result + claudeLine("api-request", time: 903))
    #expect(fixture.proof() == nil)
    try fixture.write(invoking + result + claudeLine("assistant", time: 904, id: "done", parent: "result", reason: "end_turn"))
    #expect(fixture.proof()?.status == .complete)
    try fixture.write(invoking + claudeLine("assistant", time: 904, id: "false-end", parent: "tool", reason: "end_turn"))
    #expect(fixture.proof() == nil)
}

@Test("Claude newer activity, unknown records, partial files and foreign identities preserve work",
    arguments: ["new-user", "request", "partial", "malformed", "unknown", "foreign", "old-parent", "partial-response", "tool"])
func claudeAmbiguousEvidencePreservesWork(mode: String) throws {
    let fixture = try ClaudeFixture()
    defer { fixture.remove() }
    var body = try claudeEnding()
    switch mode {
    case "new-user": body += try claudeLine("user", time: 1_100, id: "new")
    case "request": body += try claudeLine("api-request", time: 1_100)
    case "partial": body += "{\"type\":"
    case "malformed": body += "{broken}\n"
    case "unknown": body += try claudeLine("unrecognized-lifecycle", time: 1_100)
    case "foreign": body = try claudeLine("user") + claudeLine("assistant", time: 1_000,
        parent: "prompt", reason: "end_turn", session: UUID().uuidString)
    case "old-parent": body += try claudeLine("user", time: 1_100, id: "new")
        + claudeLine("assistant", time: 1_200, parent: "prompt", reason: "stop_sequence", error: true)
    case "partial-response": body += try claudeLine("assistant", time: 1_100, parent: "end")
    case "tool": body += try claudeLine("assistant", time: 1_100, parent: "end", reason: "tool_use",
        blocks: [["type": "tool_use", "id": "running"]])
    default: break
    }
    try fixture.write(body)
    #expect(fixture.proof() == nil)
}

@Test("Claude sidechain completions cannot end root work")
func claudeSubagentsDoNotEndParent() throws {
    let fixture = try ClaudeFixture()
    defer { fixture.remove() }
    try fixture.write(claudeLine("user") + claudeLine("assistant", time: 1_000,
        parent: "prompt", reason: "end_turn", extra: ["isSidechain": true]))
    #expect(fixture.proof() == nil)
    #expect(fixture.history.completion(sessionID: claudeSession,
        transcriptPath: fixture.home.appending(path: "subagents/\(claudeSession).jsonl").path, notBefore: 900) == nil)
}

@Test("Claude bounded tails can recover after an older unanchored fragment")
func claudeBoundedTailFindsLatestRequest() throws {
    let fixture = try ClaudeFixture()
    defer { fixture.remove() }
    let older = try claudeLine("assistant", time: 800, parent: "outside-tail", reason: "end_turn")
    try fixture.write(older + claudeEnding())
    #expect(fixture.proof()?.status == .error)
    try fixture.write(claudeEnding() + claudeLine("user", time: 1_100, id: "new",
        extra: ["message": ["role": "user", "content": "private string prompt"]]))
    #expect(fixture.proof() == nil)
}

@Test("Claude StopFailure displays a short error and cannot clear a newer request")
func claudeFailureHookUsesCurrentEvidence() throws {
    let fixture = try ClaudeFixture()
    defer { fixture.remove() }
    try fixture.write(claudeEnding())
    let file = AgentStateFile(url: fixture.home.appending(path: "state.json"), ownerStatus: { _ in .alive },
        claudeEvidence: { fixture.history.completion(sessionID: $0, transcriptPath: $1, notBefore: $2) })
    _ = try file.apply(.init(provider: .claudeCode, sessionID: claudeSession, status: .working,
        lifecycle: .begin, occurredAt: 900, transcriptPath: fixture.url.path), now: 900)
    let failure = AgentEvent(provider: .claudeCode, sessionID: claudeSession, status: .error,
        lifecycle: .endTurn, occurredAt: 1_001, transcriptPath: fixture.url.path)
    #expect(try file.apply(failure, now: 1_001) == .error)
    var state = try file.load()
    #expect(state.displayCommand(now: 1_001) == .error)
    #expect(state.displayCommand(now: 1_016) == .idle)
    _ = try file.apply(.init(provider: .claudeCode, sessionID: claudeSession, status: .working,
        lifecycle: .begin, occurredAt: 1_100), now: 1_100)
    try fixture.write(claudeEnding() + claudeLine("user", time: 1_100, id: "new")
        + claudeLine("api-request", time: 1_101))
    _ = try file.apply(failure, now: 1_200)
    state = try file.load()
    #expect(state.displayCommand(now: 90 * 24 * 3600) == .working)
}

@Test("Claude fallback cleans old API failures with live owners and preserves another session")
func claudeFallbackIsAutomaticAndDurable() throws {
    let fixture = try ClaudeFixture()
    defer { fixture.remove() }
    try fixture.write(claudeEnding())
    let file = AgentStateFile(url: fixture.home.appending(path: "state.json"), ownerStatus: { _ in .alive },
        claudeEvidence: { fixture.history.completion(sessionID: $0, transcriptPath: $1, notBefore: $2) })
    _ = try file.apply(.init(provider: .claudeCode, sessionID: claudeSession, status: .working), now: 900)
    _ = try file.apply(.init(provider: .codex, sessionID: "other-live", status: .working), now: 900)
    #expect(try file.load().sessions.count == 1)
    _ = try file.apply(.init(provider: .claudeCode, sessionID: claudeSession, status: .working,
        lifecycle: .activity, occurredAt: 1_100), now: 1_100)
    #expect(try file.load().sessions.count == 1)
    _ = try file.apply(.init(provider: .claudeCode, sessionID: claudeSession, status: .waiting,
        lifecycle: .begin, occurredAt: 1_200), now: 1_200)
    var state = try file.load()
    #expect(state.sessions.count == 2)
    #expect(state.displayCommand(now: 90 * 24 * 3600) == .waiting)
}

@Test("Claude missing or unreadable evidence never ends a long task")
func claudeMissingEvidencePreservesWork() throws {
    let fixture = try ClaudeFixture()
    defer { fixture.remove() }
    let file = AgentStateFile(url: fixture.home.appending(path: "state.json"), ownerStatus: { _ in .alive },
        claudeEvidence: { fixture.history.completion(sessionID: $0, transcriptPath: $1, notBefore: $2) })
    _ = try file.apply(.init(provider: .claudeCode, sessionID: claudeSession, status: .working,
        lifecycle: .begin, occurredAt: 900), now: 900)
    _ = try file.apply(.init(provider: .claudeCode, sessionID: claudeSession, status: .error,
        lifecycle: .endTurn, occurredAt: 1_000), now: 1_000)
    var state = try file.load()
    #expect(state.displayCommand(now: 90 * 24 * 3600) == .working)
}

@Test("Claude fallback catches an ending written after its hook without another event")
func claudeLogFlushAfterHook() throws {
    let fixture = try ClaudeFixture()
    defer { fixture.remove() }
    let file = AgentStateFile(url: fixture.home.appending(path: "state.json"), ownerStatus: { _ in .alive },
        claudeEvidence: { fixture.history.completion(sessionID: $0, transcriptPath: $1, notBefore: $2) })
    _ = try file.apply(.init(provider: .claudeCode, sessionID: claudeSession, status: .working,
        lifecycle: .begin, occurredAt: 900, transcriptPath: fixture.url.path), now: 900)
    _ = try file.apply(.init(provider: .claudeCode, sessionID: claudeSession, status: .error,
        lifecycle: .endTurn, occurredAt: 1_001), now: 1_001)
    #expect(try file.load().sessions.count == 1)
    try fixture.write(claudeEnding())
    #expect(try file.load().sessions.isEmpty)
}

@Test("Claude closed sessions reject late notifications, while new prompts remain active")
func claudeClosedSessionFencing() {
    var state = AgentState()
    let key = AgentSessionKey(provider: .claudeCode, sessionID: claudeSession)
    state.apply(.init(provider: .claudeCode, sessionID: claudeSession, status: .working,
        lifecycle: .begin, occurredAt: 900), now: 900)
    #expect(state.reconcileClaudeSessions(now: 2_000, check: { _, _, _ in
        ClaudeTurnEvidence(endedAt: 1_000, status: .error)
    }) == 1)
    state.apply(.init(provider: .claudeCode, sessionID: claudeSession, status: .waiting,
        lifecycle: .activity, occurredAt: 1_100), now: 1_100)
    state.apply(.init(provider: .claudeCode, sessionID: claudeSession, status: .working,
        lifecycle: .begin, occurredAt: 950), now: 1_200)
    #expect(state.sessions[key] == nil)
    state.apply(.init(provider: .claudeCode, sessionID: claudeSession, status: .working,
        lifecycle: .begin, occurredAt: 1_300), now: 1_300)
    #expect(state.sessions[key]?.status == .working)
    #expect(state.reconcileClaudeSessions(now: 90 * 24 * 3600, check: { _, _, _ in
        ClaudeTurnEvidence(endedAt: 1_000, status: .error)
    }) == 0)
}

@Test("Claude late activity cannot transfer a new task to an exited older owner")
func claudeOwnerHandoffsPreserveWork() {
    let old = AgentProcessOwner(pid: 42, startedSeconds: 1, startedMicroseconds: 0)
    let current = AgentProcessOwner(pid: 43, startedSeconds: 2, startedMicroseconds: 0)
    var state = AgentState()
    state.apply(.init(provider: .claudeCode, sessionID: claudeSession, status: .working,
        lifecycle: .begin, owner: current, occurredAt: 1_000), now: 1_000)
    state.apply(.init(provider: .claudeCode, sessionID: claudeSession, status: .working,
        lifecycle: .activity, owner: old, occurredAt: 1_100), now: 1_100)
    #expect(state.reconcileOwners(check: { $0 == old ? .exited : .alive }) == 0)
    #expect(state.displayCommand(now: 90 * 24 * 3600) == .working)
}

@Test("Claude large earlier messages do not require unbounded reads")
func claudeBoundedReads() throws {
    let fixture = try ClaudeFixture()
    defer { fixture.remove() }
    let large = try claudeLine("user", time: 800,
        blocks: [["type": "text", "text": String(repeating: "x", count: 30_000)]])
    try fixture.write(large + claudeEnding())
    let history = ClaudeTurnHistory(home: fixture.home, tailLimit: 2048)
    #expect(history.completion(sessionID: claudeSession, transcriptPath: nil, notBefore: 900)?.status == .error)
    try fixture.write(claudeEnding() + large)
    #expect(history.completion(sessionID: claudeSession, transcriptPath: nil, notBefore: 900) == nil)
}
