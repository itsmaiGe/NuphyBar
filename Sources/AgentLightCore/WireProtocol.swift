public enum AgentLightCommand: Equatable, Sendable {
    case idle
    case working
    case waiting
    case complete
    case error
}

public enum DirectStatusEncoder {
    private static let capsLock: UInt8 = 0x02

    public static func encode(_ command: AgentLightCommand, capsLockOn: Bool) -> UInt8 {
        let caps = capsLockOn ? capsLock : 0
        switch command {
        case .idle: return caps
        case .working: return caps | 0x01
        case .waiting, .error: return caps | 0x04
        case .complete: return caps | 0x05
        }
    }
}
