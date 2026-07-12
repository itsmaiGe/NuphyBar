public enum CommandLineRequest: Equatable, Sendable {
    case describe
    case send(AgentLightCommand)

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
}

public enum CommandLineError: Error, Equatable, CustomStringConvertible {
    case missingCommand
    case invalidCommand
    case invalidProgress
    case invalidColor

    public var description: String {
        switch self {
        case .missingCommand, .invalidCommand:
            return "usage: agentlight describe | idle | working | waiting | complete | error | heartbeat | progress 0...5 | color RRGGBB"
        case .invalidProgress:
            return "progress must be a whole number from 0 through 5"
        case .invalidColor:
            return "color must be a six-digit hexadecimal RGB value, for example 00A0FF"
        }
    }
}
