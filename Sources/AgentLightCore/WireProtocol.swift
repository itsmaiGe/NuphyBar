public enum AgentLightCommand: Equatable, Sendable {
    case idle
    case working
    case toolRunning
    case outputting
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
        case .working, .toolRunning, .outputting: return caps | 0x01
        case .waiting, .error: return caps | 0x04
        case .complete: return caps | 0x05
        }
    }
}

public enum Halo75V2RawHIDProtocol {
    public static let reportLength = 32

    private static let signature: [UInt8] = [0x4E, 0x42]
    private static let version: UInt8 = 0x01
    private static let setState: UInt8 = 0x01

    public static func encode(_ command: AgentLightCommand) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: reportLength)
        report[0] = signature[0]
        report[1] = signature[1]
        report[2] = version
        report[3] = setState
        report[4] = stateCode(command)
        report[reportLength - 1] = checksum(report.dropLast())
        return report
    }

    public static func hasValidChecksum(_ report: [UInt8]) -> Bool {
        guard report.count == reportLength else { return false }
        return checksum(report.dropLast()) == report[reportLength - 1]
    }

    private static func stateCode(_ command: AgentLightCommand) -> UInt8 {
        switch command {
        case .idle: return 0
        case .working: return 1
        case .toolRunning: return 2
        case .outputting: return 3
        case .waiting: return 4
        case .complete: return 5
        case .error: return 6
        }
    }

    private static func checksum<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        bytes.reduce(0, ^)
    }
}

public enum AULAF99ProRealtimeProtocol {
    public static let reportID = 0x13
    public static let reportLength = 20

    public static func encode(_ command: AgentLightCommand) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: reportLength)
        report[0] = UInt8(reportID)
        if command == .idle {
            report[1] = 0x03
            report[reportLength - 1] = checksum(report.dropLast())
            return report
        }

        let color = color(for: command)
        report[1] = 0x88
        report[2] = 0x01
        report[4] = 0x23
        report[5] = color.red
        report[6] = color.green
        report[7] = color.blue
        report[reportLength - 1] = checksum(report.dropLast())
        return report
    }

    public static func hasValidChecksum(_ report: [UInt8]) -> Bool {
        guard report.count == reportLength else { return false }
        return checksum(report.dropLast()) == report[reportLength - 1]
    }

    private static func color(for command: AgentLightCommand) -> (red: UInt8, green: UInt8, blue: UInt8) {
        switch command {
        case .idle: return (0x00, 0x00, 0x00)
        case .complete: return (0x00, 0xFF, 0x00)
        case .working: return (0xFF, 0x00, 0x00)
        case .toolRunning: return (0xFF, 0x00, 0x00)
        case .outputting: return (0xFF, 0xB0, 0x00)
        case .waiting: return (0x00, 0x66, 0xFF)
        case .error: return (0xFF, 0x00, 0x00)
        }
    }

    private static func checksum<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        UInt8(truncatingIfNeeded: bytes.reduce(0) { $0 + UInt16($1) })
    }
}
