import Foundation

public enum HookEventError: Error, Equatable {
    case invalidPayload
}

public enum HookEventMapper {
    public static func map(provider: AgentProvider, eventName: String, payload: Data) throws -> AgentEvent? {
        if (provider == .claudeCode || provider == .grokBuild), eventName == "Notification" {
            guard let input = try? JSONDecoder().decode(HookInput.self, from: payload),
                  let sessionID = input.resolvedSessionID, !sessionID.isEmpty else {
                throw HookEventError.invalidPayload
            }
            guard input.resolvedNotificationType == "agent_needs_input"
                    || input.resolvedNotificationType == "elicitation_dialog" else { return nil }
            return AgentEvent(provider: provider, sessionID: sessionID, status: .waiting)
        }

        guard let status = status(provider: provider, eventName: eventName) else { return nil }
        guard let input = try? JSONDecoder().decode(HookInput.self, from: payload),
              let sessionID = input.resolvedSessionID, !sessionID.isEmpty else {
            throw HookEventError.invalidPayload
        }
        return AgentEvent(provider: provider, sessionID: sessionID, status: status)
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
        case (.claudeCode, "PermissionRequest"):
            return .waiting
        case (.claudeCode, "Stop"):
            return .complete
        case (.claudeCode, "SessionEnd"):
            return .idle
        case (.grokBuild, "UserPromptSubmit"), (.grokBuild, "PreToolUse"), (.grokBuild, "PostToolUse"):
            return .working
        case (.grokBuild, "Stop"):
            return .complete
        case (.grokBuild, "StopFailure"), (.grokBuild, "PostToolUseFailure"), (.grokBuild, "PermissionDenied"):
            return .error
        case (.grokBuild, "SessionEnd"):
            return .idle
        default:
            return nil
        }
    }
}

private struct HookInput: Decodable {
    let sessionID: String?
    let camelCaseSessionID: String?
    let notificationType: String?
    let camelCaseNotificationType: String?

    var resolvedSessionID: String? { sessionID ?? camelCaseSessionID }
    var resolvedNotificationType: String? { notificationType ?? camelCaseNotificationType }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case camelCaseSessionID = "sessionId"
        case notificationType = "notification_type"
        case camelCaseNotificationType = "notificationType"
    }
}
