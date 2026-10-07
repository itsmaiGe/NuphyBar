import CryptoKit
import Darwin
import Foundation
import OSLog

public final class RecoveryDiagnostics: @unchecked Sendable {
    public static let shared = RecoveryDiagnostics(url: AgentStateFile.defaultURL
        .deletingLastPathComponent().appending(path: "recovery-diagnostics.json"))

    public struct Entry: Codable, Sendable {
        public let time: TimeInterval
        public let event: String
        public let fields: [String: String]
    }

    private let url: URL?
    private let capacity: Int
    private let lock = NSLock()
    private var entries: [Entry] = []
    private let logger = Logger(subsystem: "com.maige.NuphyBar", category: "Recovery")

    public init(url: URL? = nil, capacity: Int = 512) {
        self.url = url
        self.capacity = max(1, capacity)
    }

    public static func anonymousID(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    public func record(_ event: String, fields: [String: String] = [:]) {
        let entry = Entry(time: Date().timeIntervalSince1970, event: String(event.prefix(80)),
            fields: Dictionary(uniqueKeysWithValues: fields.sorted { $0.key < $1.key }.prefix(20)
                .map { ($0.key, String($0.value.prefix(256))) }))
        do {
            try lock.withLock {
                try withFileLock {
                    var recent = try readEntries()
                    recent.append(entry)
                    entries = Array(recent.suffix(capacity))
                    if let url {
                        try JSONEncoder().encode(entries).write(to: url, options: [.atomic])
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                    }
                }
            }
        } catch {
            logger.error("Could not store recovery diagnostic: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func export() throws -> Data {
        try lock.withLock {
            try withFileLock {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                return try encoder.encode(readEntries())
            }
        }
    }

    private func readEntries() throws -> [Entry] {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return entries }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 4 * 1024 * 1024 else { return entries }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode([Entry].self, from: data)
        } catch {
            throw AgentStateFileError.invalidState
        }
    }

    private func withFileLock<T>(_ operation: () throws -> T) throws -> T {
        guard let url else { return try operation() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // An integration installer may spawn a child while this lock is held.
        // Do not let that child retain the journal lock after this call returns.
        let descriptor = Darwin.open(url.appendingPathExtension("lock").path,
            O_CREAT | O_RDWR | O_EXLOCK | O_NONBLOCK | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw AgentStateFileError.lockOpenFailed }
        defer { Darwin.close(descriptor) }
        return try operation()
    }
}
