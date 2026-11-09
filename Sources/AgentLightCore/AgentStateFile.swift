import Darwin
import Foundation

public enum AgentStateFileError: Error, LocalizedError {
    case lockOpenFailed
    case lockFailed
    case invalidState

    public var errorDescription: String? {
        switch self {
        case .lockOpenFailed, .lockFailed: return "无法锁定任务状态文件"
        case .invalidState: return "任务状态文件无法读取，原文件已保留"
        }
    }
}

public struct AgentStateFile: Sendable {
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "AgentLight", directoryHint: .isDirectory)
            .appending(path: "state-v2.json")
    }

    public let url: URL
    private let ownerStatus: @Sendable (AgentProcessOwner) -> AgentOwnerStatus
    private let turnEvidence: @Sendable (String, String, Double) -> CodexTurnEvidence?
    private let claudeEvidence: @Sendable (String, String?, Double) -> ClaudeTurnEvidence?

    public init(url: URL = Self.defaultURL,
                ownerStatus: @escaping @Sendable (AgentProcessOwner) -> AgentOwnerStatus = { $0.status() },
                turnEvidence: @escaping @Sendable (String, String, Double) -> CodexTurnEvidence? = {
                    CodexTurnHistory.shared.completion(sessionID: $0, turnID: $1, beganAt: $2)
                },
                claudeEvidence: @escaping @Sendable (String, String?, Double) -> ClaudeTurnEvidence? = {
                    ClaudeTurnHistory.shared.completion(sessionID: $0, transcriptPath: $1, notBefore: $2)
                }) {
        self.url = url
        self.ownerStatus = ownerStatus
        self.turnEvidence = turnEvidence
        self.claudeEvidence = claudeEvidence
    }

    public func load() throws -> AgentState {
        try withLock {
            var state = try loadUnlocked()
            let removed = state.reconcileOwners(check: ownerStatus)
            let ended = state.reconcileCodexTurns(check: turnEvidence)
            let claudeEnded = state.reconcileClaudeSessions(now: Int64(Date().timeIntervalSince1970), check: claudeEvidence)
            if removed > 0 || ended > 0 || claudeEnded > 0 {
                try saveUnlocked(state)
                if url == Self.defaultURL {
                    if removed > 0 {
                        RecoveryDiagnostics.shared.record("state.owner.exited", fields: ["removed": String(removed)])
                    }
                    if ended > 0 {
                        RecoveryDiagnostics.shared.record("state.turn.ended", fields: ["removed": String(ended)])
                    }
                    if claudeEnded > 0 {
                        RecoveryDiagnostics.shared.record("state.claude.ended", fields: ["ended": String(claudeEnded)])
                    }
                }
            }
            return state
        }
    }

    public func apply(_ event: AgentEvent, now: Int64) throws -> AgentLightCommand? {
        try withLock {
            var state = try loadUnlocked()
            let previous = state.displayCommand(now: now)
            if event.provider == .claudeCode, event.lifecycle == .endTurn || event.lifecycle == .endSession {
                let key = AgentSessionKey(provider: .claudeCode, sessionID: event.sessionID)
                if state.sessions[key]?.transcriptPath == nil, let path = event.transcriptPath {
                    state.sessions[key]?.transcriptPath = path
                }
                _ = state.reconcileClaudeSessions(now: now) { session, path, threshold in
                    guard session == event.sessionID else { return nil }
                    return claudeEvidence(session, path, threshold)
                }
            } else {
                state.apply(event, now: now)
            }
            let command = state.displayCommand(now: now)
            try saveUnlocked(state)
            return command == previous ? nil : command
        }
    }

    public func record(_ event: AgentEvent, now: Int64) throws -> AgentLightCommand? {
        let command = try apply(event, now: now)
        AgentStateChangeNotification.post()
        return command
    }

    private func loadUnlocked() throws -> AgentState {
        guard FileManager.default.fileExists(atPath: url.path) else { return AgentState() }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(AgentState.self, from: data)
        } catch {
            throw AgentStateFileError.invalidState
        }
    }

    private func saveUnlocked(_ state: AgentState) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appending(path: "state.lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw AgentStateFileError.lockOpenFailed }
        defer { Darwin.close(descriptor) }
        guard Darwin.lockf(descriptor, F_LOCK, 0) == 0 else { throw AgentStateFileError.lockFailed }
        defer { Darwin.lockf(descriptor, F_ULOCK, 0) }
        return try operation()
    }
}
