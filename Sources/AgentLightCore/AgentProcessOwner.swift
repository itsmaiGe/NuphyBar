import Darwin
import Foundation

public enum AgentOwnerStatus: Sendable { case alive, exited, unknown }

public struct AgentProcessOwner: Codable, Equatable, Sendable {
    public let pid: Int32
    public let startedSeconds: UInt64
    public let startedMicroseconds: UInt64

    public init(pid: Int32, startedSeconds: UInt64, startedMicroseconds: UInt64) {
        self.pid = pid
        self.startedSeconds = startedSeconds
        self.startedMicroseconds = startedMicroseconds
    }

    public static func capture(provider: AgentProvider) -> AgentProcessOwner? {
        var pid = getppid()
        for _ in 0..<64 {
            guard pid > 1, let info = information(pid) else { return nil }
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let size = path.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
            guard size > 0 else { return nil }
            let name = String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let executable = URL(fileURLWithPath: name).lastPathComponent
            let matches: Bool
            switch provider {
            case .codex: matches = executable == "codex" || executable == "Codex (Service)"
            case .claudeCode: matches = executable == "claude" || executable == "claude-code"
            default: matches = false
            }
            if matches { return identity(pid, info) }
            let parent = Int32(info.pbi_ppid)
            guard parent != pid else { return nil }
            pid = parent
        }
        return nil
    }

    public func status() -> AgentOwnerStatus {
        guard pid > 1 else { return .unknown }
        if let info = Self.information(pid) {
            guard Self.identity(pid, info) == self else { return .exited }
            return info.pbi_status == SZOMB ? .exited : .alive
        }
        // An access failure is not evidence that the recorded owner exited.
        if kill(pid, 0) == -1, errno == ESRCH { return .exited }
        return .unknown
    }

    public static var invocationTime: Double? {
        guard let info = information(getpid()) else { return nil }
        return Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000
    }

    private static func information(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let expected = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expected) == expected else { return nil }
        return info
    }

    private static func identity(_ pid: Int32, _ info: proc_bsdinfo) -> AgentProcessOwner {
        AgentProcessOwner(pid: pid, startedSeconds: info.pbi_start_tvsec,
            startedMicroseconds: info.pbi_start_tvusec)
    }
}
