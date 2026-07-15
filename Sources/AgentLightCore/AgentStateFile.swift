import Darwin
import Foundation

public enum AgentStateFileError: Error {
    case lockOpenFailed
    case lockFailed
}

public struct AgentStateFile: Sendable {
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "AgentLight", directoryHint: .isDirectory)
            .appending(path: "state.json")
    }

    public let url: URL

    public init(url: URL = Self.defaultURL) {
        self.url = url
    }

    public func load() throws -> AgentState {
        try withLock { try loadUnlocked() }
    }

    public func apply(_ event: AgentEvent, now: Int64) throws -> AgentLightCommand? {
        try withLock {
            var state = try loadUnlocked()
            let previous = state.displayCommand(now: now)
            state.apply(event, now: now)
            let command = state.displayCommand(now: now)
            try saveUnlocked(state)
            return command == previous ? nil : command
        }
    }

    public func record(_ event: AgentEvent, now: Int64) throws -> AgentLightCommand? {
        let command = try apply(event, now: now)
        AgentStateChangeNotification.post()
        return command
    }

    private func loadUnlocked() throws -> AgentState {
        guard FileManager.default.fileExists(atPath: url.path) else { return AgentState() }
        let data = try Data(contentsOf: url)
        return (try? JSONDecoder().decode(AgentState.self, from: data)) ?? AgentState()
    }

    private func saveUnlocked(_ state: AgentState) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appending(path: "state.lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw AgentStateFileError.lockOpenFailed }
        defer { Darwin.close(descriptor) }
        guard Darwin.lockf(descriptor, F_LOCK, 0) == 0 else { throw AgentStateFileError.lockFailed }
        defer { Darwin.lockf(descriptor, F_ULOCK, 0) }
        return try operation()
    }
}
