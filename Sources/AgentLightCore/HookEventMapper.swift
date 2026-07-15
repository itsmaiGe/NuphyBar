import Foundation

public enum HookEventError: Error, Equatable {
    case invalidPayload
}

public enum HookEventMapper {
    public static func map(provider: AgentProvider, eventName: String, payload: Data) throws -> AgentEvent? {
        if provider == .antigravity {
            guard let input = try? JSONDecoder().decode(HookInput.self, from: payload),
                  let sessionID = input.resolvedSessionID, !sessionID.isEmpty else {
                throw HookEventError.invalidPayload
            }

            let status: AgentSessionStatus?
            switch eventName {
            case "PreInvocation":
                status = .working
            case "Stop" where input.hasError:
                status = .error
            case "Stop" where input.fullyIdle == false:
                status = .working
            case "Stop" where input.fullyIdle == true:
                status = .complete
            default:
                status = nil
            }
            return status.map { AgentEvent(provider: provider, sessionID: sessionID, status: $0) }
        }

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

    public static func response(provider: AgentProvider, eventName: String) -> Data? {
        guard provider == .antigravity else { return nil }
        switch eventName {
        case "PreInvocation": return Data("{}".utf8)
        case "Stop": return Data(#"{"decision":"stop"}"#.utf8)
        default: return nil
        }
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
    let conversationID: String?
    let fullyIdle: Bool?
    let terminationReason: String?
    let error: String?

    var resolvedSessionID: String? { sessionID ?? camelCaseSessionID ?? conversationID }
    var resolvedNotificationType: String? { notificationType ?? camelCaseNotificationType }
    var hasError: Bool {
        terminationReason == "error" || !(error ?? "").isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case camelCaseSessionID = "sessionId"
        case notificationType = "notification_type"
        case camelCaseNotificationType = "notificationType"
        case conversationID = "conversationId"
        case fullyIdle
        case terminationReason
        case error
    }
}
