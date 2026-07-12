public enum AgentLightCommand: Equatable, Sendable {
    case idle
    case working
    case waiting
    case complete
    case error
    case progress(UInt8)
    case color(red: UInt8, green: UInt8, blue: UInt8)
    case completionDuration(seconds: UInt8)
    case heartbeat
}

public enum WireProtocolError: Error, Equatable {
    case invalidSync
    case unsupportedVersion
    case invalidLength
    case invalidChecksum
    case invalidCommand
}

public enum WireFrame {
    public static let sync: [UInt8] = [0xA7, 0xD3]
    public static let version: UInt8 = 0x01

    public static func encode(_ command: AgentLightCommand) -> [UInt8] {
        let body = commandBody(command)
        var frame = sync + [version, body.opcode, UInt8(body.payload.count)] + body.payload
        frame.append(crc8(frame.dropFirst(sync.count)))
        return frame
    }

    public static func decode(_ frame: [UInt8]) throws -> AgentLightCommand {
        guard frame.count >= 6, Array(frame.prefix(2)) == sync else {
            throw WireProtocolError.invalidSync
        }
        guard frame[2] == version else {
            throw WireProtocolError.unsupportedVersion
        }

        let payloadLength = Int(frame[4])
        guard frame.count == 6 + payloadLength else {
            throw WireProtocolError.invalidLength
        }
        guard crc8(frame.dropFirst(2).dropLast()) == frame.last else {
            throw WireProtocolError.invalidChecksum
        }

        let payload = Array(frame[5..<(5 + payloadLength)])
        switch frame[3] {
        case 0x10 where payload.isEmpty: return .idle
        case 0x11 where payload.isEmpty: return .working
        case 0x12 where payload.isEmpty: return .waiting
        case 0x13 where payload.isEmpty: return .complete
        case 0x14 where payload.isEmpty: return .error
        case 0x20 where payload.count == 1 && payload[0] <= 5:
            return .progress(payload[0])
        case 0x30 where payload.count == 3:
            return .color(red: payload[0], green: payload[1], blue: payload[2])
        case 0x31 where payload.count == 1 && (3...60).contains(payload[0]):
            return .completionDuration(seconds: payload[0])
        case 0x40 where payload.isEmpty: return .heartbeat
        default: throw WireProtocolError.invalidCommand
        }
    }

    public static func crc8<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        var crc: UInt8 = 0
        for byte in bytes {
            crc ^= byte
            for _ in 0..<8 {
                crc = crc & 0x80 == 0 ? crc << 1 : (crc << 1) ^ 0x07
            }
        }
        return crc
    }

    private static func commandBody(_ command: AgentLightCommand) -> (opcode: UInt8, payload: [UInt8]) {
        switch command {
        case .idle: return (0x10, [])
        case .working: return (0x11, [])
        case .waiting: return (0x12, [])
        case .complete: return (0x13, [])
        case .error: return (0x14, [])
        case .progress(let value): return (0x20, [min(value, 5)])
        case .color(let red, let green, let blue): return (0x30, [red, green, blue])
        case .completionDuration(let seconds): return (0x31, [min(max(seconds, 3), 60)])
        case .heartbeat: return (0x40, [])
        }
    }
}

public enum HIDReportEncoder {
    private static let numLock: UInt8 = 0x01
    private static let capsLock: UInt8 = 0x02
    private static let scrollLock: UInt8 = 0x04

    public static func encode(_ frame: [UInt8], capsLockOn: Bool) -> [UInt8] {
        let caps = capsLockOn ? capsLock : 0
        var reports = [caps]
        var clockHigh = false

        for byte in frame {
            for bitIndex in (0..<8).reversed() {
                clockHigh.toggle()
                let data = byte & (1 << bitIndex) == 0 ? UInt8(0) : numLock
                let clock = clockHigh ? scrollLock : 0
                reports.append(caps | clock | data)
            }
        }
        return reports
    }
}

public enum CompactStatusEncoder {
    private static let capsLock: UInt8 = 0x02

    public static func encode(_ command: AgentLightCommand, capsLockOn: Bool) -> [UInt8]? {
        guard let code = compactCode(command) else { return nil }
        let caps = capsLockOn ? capsLock : 0
        var reports: [UInt8] = [caps, caps | 0x01, caps | 0x04, caps | 0x05]
        var state: UInt8 = 3

        for divisor: UInt8 in [9, 3, 1] {
            let digit = (code / divisor) % 3
            state = (state + digit + 1) % 4
            let mask = (state & 0x01) | ((state & 0x02) << 1)
            reports.append(caps | mask)
        }
        reports.append(caps)
        return reports
    }

    private static func compactCode(_ command: AgentLightCommand) -> UInt8? {
        switch command {
        case .idle: return 0
        case .working: return 1
        case .waiting: return 2
        case .complete: return 3
        case .error: return 4
        case .progress(let value): return 5 + min(value, 5)
        case .color, .completionDuration, .heartbeat: return nil
        }
    }
}
