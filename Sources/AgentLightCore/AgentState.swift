public enum AgentProvider: String, Codable, CaseIterable, Sendable {
    case codex
    case claudeCode = "claude-code"
    case openCode = "opencode"
    case grokBuild = "grok-build"
    case hermes
    case openClaw = "openclaw"
    case antigravity
}

public enum AgentSessionStatus: Codable, Equatable, Sendable {
    case idle
    case working
    case waiting
    case complete
    case error
}

public struct AgentSessionKey: Codable, Hashable, Sendable {
    public let provider: AgentProvider
    public let sessionID: String

    public init(provider: AgentProvider, sessionID: String) {
        self.provider = provider
        self.sessionID = sessionID
    }
}

public struct AgentEvent: Equatable, Sendable {
    public let provider: AgentProvider
    public let sessionID: String
    public let status: AgentSessionStatus

    public init(provider: AgentProvider, sessionID: String, status: AgentSessionStatus) {
        self.provider = provider
        self.sessionID = sessionID
        self.status = status
    }
}

public struct AgentSessionRecord: Codable, Equatable, Sendable {
    public var status: AgentSessionStatus
    public var updatedAt: Int64
}

public struct AgentState: Codable, Equatable, Sendable {
    public static let completionRetention: Int64 = 15
    public static let activeRetention: Int64 = 15 * 60

    public var sessions: [AgentSessionKey: AgentSessionRecord]

    public init(sessions: [AgentSessionKey: AgentSessionRecord] = [:]) {
        self.sessions = sessions
    }

    public mutating func apply(_ event: AgentEvent, now: Int64) {
        prune(now: now)
        let key = AgentSessionKey(provider: event.provider, sessionID: event.sessionID)
        if event.status == .idle {
            sessions.removeValue(forKey: key)
        } else {
            sessions[key] = AgentSessionRecord(status: event.status, updatedAt: now)
        }
    }

    public mutating func displayCommand(now: Int64) -> AgentLightCommand {
        prune(now: now)
        let records = sessions.values

        if records.contains(where: { $0.status == .error }) { return .error }
        if records.contains(where: { $0.status == .waiting }) { return .waiting }
        if records.contains(where: { $0.status == .working }) { return .working }

        if records.contains(where: { $0.status == .complete }) { return .complete }
        return .idle
    }

    private mutating func prune(now: Int64) {
        sessions = sessions.filter { _, record in
            let age = max(0, now - record.updatedAt)
            switch record.status {
            case .idle: return false
            case .complete, .error: return age <= Self.completionRetention
            case .working, .waiting:
                return age <= Self.activeRetention
            }
        }
    }
}
