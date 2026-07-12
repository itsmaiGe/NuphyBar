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
        case "heartbeat" where arguments.count == 1: return .send(.heartbeat)
        case "progress" where arguments.count == 2:
            guard let value = UInt8(arguments[1]), value <= 5 else {
                throw CommandLineError.invalidProgress
            }
            return .send(.progress(value))
        case "color" where arguments.count == 2:
            return .send(try parseColor(arguments[1]))
        case "hook" where arguments.count == 3:
            guard let provider = AgentProvider(rawValue: arguments[1]), provider != .openCode else {
                throw CommandLineError.invalidProvider
            }
            return .hook(provider, arguments[2])
        case "event" where arguments.count == 4 || arguments.count == 5:
            guard let provider = AgentProvider(rawValue: arguments[1]) else {
                throw CommandLineError.invalidProvider
            }
            let status = try parseStatus(arguments)
            return .event(AgentEvent(provider: provider, sessionID: arguments[3], status: status))
        default:
            throw CommandLineError.invalidCommand
        }
    }

    private static func parseColor(_ text: String) throws -> AgentLightCommand {
        let hex = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else {
            throw CommandLineError.invalidColor
        }
        return .color(
            red: UInt8((value >> 16) & 0xFF),
            green: UInt8((value >> 8) & 0xFF),
            blue: UInt8(value & 0xFF)
        )
    }

    private static func parseStatus(_ arguments: [String]) throws -> AgentSessionStatus {
        switch arguments[2] {
        case "idle" where arguments.count == 4: return .idle
        case "working" where arguments.count == 4: return .working
        case "waiting" where arguments.count == 4: return .waiting
        case "complete" where arguments.count == 4: return .complete
        case "error" where arguments.count == 4: return .error
        case "progress" where arguments.count == 5:
            guard let value = UInt8(arguments[4]), value <= 5 else {
                throw CommandLineError.invalidProgress
            }
            return .progress(value)
        default:
            throw CommandLineError.invalidCommand
        }
    }
}

public enum CommandLineError: Error, Equatable, CustomStringConvertible {
    case missingCommand
    case invalidCommand
    case invalidProgress
    case invalidColor
    case invalidProvider

    public var description: String {
        switch self {
        case .missingCommand, .invalidCommand:
            return "usage: agent-light describe | idle | working | waiting | complete | error | heartbeat | progress 0...5 | color RRGGBB | hook PROVIDER EVENT | event PROVIDER STATUS SESSION"
        case .invalidProgress:
            return "progress must be a whole number from 0 through 5"
        case .invalidColor:
            return "color must be a six-digit hexadecimal RGB value, for example 00A0FF"
        case .invalidProvider:
            return "provider must be codex, claude-code, or opencode"
        }
    }
}
