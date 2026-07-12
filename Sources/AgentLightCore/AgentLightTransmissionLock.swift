import Darwin
import Foundation

public enum AgentLightTransmissionLockError: LocalizedError {
    case openFailed

    public var errorDescription: String? {
        "无法锁定 Agent Light 蓝牙发送通道"
    }
}

public struct AgentLightTransmissionLock: Sendable {
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "AgentLight", directoryHint: .isDirectory)
            .appending(path: "transmission.lock")
    }

    public let url: URL

    public init(url: URL = Self.defaultURL) {
        self.url = url
    }

    public func withLock<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = Darwin.open(
            url.path,
            O_CREAT | O_RDWR | O_EXLOCK,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw AgentLightTransmissionLockError.openFailed }
        defer { Darwin.close(descriptor) }
        return try operation()
    }
}
