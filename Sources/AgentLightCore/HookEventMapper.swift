import Foundation

public enum HookEventError: Error, Equatable {
    case invalidPayload
}

public enum HookEventMapper {
    public static func map(provider: AgentProvider, eventName: String, payload: Data) throws -> AgentEvent? {
        guard let status = status(provider: provider, eventName: eventName) else { return nil }
        guard let input = try? JSONDecoder().decode(HookInput.self, from: payload),
              !input.sessionID.isEmpty else {
            throw HookEventError.invalidPayload
        }
        return AgentEvent(provider: provider, sessionID: input.sessionID, status: status)
    }

    private static func status(provider: AgentProvider, eventName: String) -> AgentSessionStatus? {
        switch (provider, eventName) {
        case (.codex, "UserPromptSubmit"), (.codex, "PreToolUse"), (.codex, "PostToolUse"):
            return .working
        case (.codex, "PermissionRequest"):
            return .waiting
        case (.codex, "Stop"):
            return .complete
        case (.claudeCode, "UserPromptSubmit"), (.claudeCode, "PreToolUse"), (.claudeCode, "PostToolUse"):
            return .working
        case (.claudeCode, "PermissionRequest"), (.claudeCode, "Notification"):
            return .waiting
        case (.claudeCode, "Stop"):
            return .complete
        case (.claudeCode, "SessionEnd"):
            return .idle
        default:
            return nil
        }
    }
}

private struct HookInput: Decodable {
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
    }
}
