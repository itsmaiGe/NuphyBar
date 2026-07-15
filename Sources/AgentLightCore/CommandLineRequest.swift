public enum CommandLineRequest: Equatable, Sendable {
    case describe
    case send(AgentLightCommand)
    case hook(AgentProvider, String)
    case event(AgentEvent)

    public static func parse(_ arguments: [String]) throws -> CommandLineRequest {
        guard let command = arguments.first else { throw CommandLineError.missingCommand }

        switch command {
        case "describe" where arguments.count == 1: return .describe
        case "idle" where arguments.count == 1: return .send(.idle)
        case "working" where arguments.count == 1: return .send(.working)
        case "waiting" where arguments.count == 1: return .send(.waiting)
        case "complete" where arguments.count == 1: return .send(.complete)
        case "error" where arguments.count == 1: return .send(.error)
        case "hook" where arguments.count == 3:
            guard let provider = AgentProvider(rawValue: arguments[1]),
                  provider == .codex || provider == .claudeCode || provider == .grokBuild
                    || provider == .antigravity else {
                throw CommandLineError.invalidProvider
            }
            return .hook(provider, arguments[2])
        case "event" where arguments.count == 4:
            guard let provider = AgentProvider(rawValue: arguments[1]) else {
                throw CommandLineError.invalidProvider
            }
            let status = try parseStatus(arguments)
            return .event(AgentEvent(provider: provider, sessionID: arguments[3], status: status))
        default:
            throw CommandLineError.invalidCommand
        }
    }

    private static func parseStatus(_ arguments: [String]) throws -> AgentSessionStatus {
        switch arguments[2] {
        case "idle" where arguments.count == 4: return .idle
        case "working" where arguments.count == 4: return .working
        case "waiting" where arguments.count == 4: return .waiting
        case "complete" where arguments.count == 4: return .complete
        case "error" where arguments.count == 4: return .error
        default:
            throw CommandLineError.invalidCommand
        }
    }
}

public enum CommandLineError: Error, Equatable, CustomStringConvertible {
    case missingCommand
    case invalidCommand
    case invalidProvider

    public var description: String {
        switch self {
        case .missingCommand, .invalidCommand:
            return "usage: agent-light describe | idle | working | waiting | complete | error | hook PROVIDER EVENT | event PROVIDER STATUS SESSION"
        case .invalidProvider:
            return "provider must be codex, claude-code, opencode, grok-build, hermes, openclaw, or antigravity"
        }
    }
}
