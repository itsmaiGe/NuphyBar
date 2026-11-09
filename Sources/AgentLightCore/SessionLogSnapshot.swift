import Darwin
import Foundation

enum SessionLogSnapshot {
    static let tailLimit = 2 * 1024 * 1024

    struct Version: Equatable {
        let device: Int64
        let inode: UInt64
        let size: UInt64
        let seconds: Int64
        let nanoseconds: Int64

        init(_ value: stat) {
            device = Int64(value.st_dev)
            inode = UInt64(value.st_ino)
            size = UInt64(max(0, value.st_size))
            seconds = Int64(value.st_mtimespec.tv_sec)
            nanoseconds = Int64(value.st_mtimespec.tv_nsec)
        }
    }

    struct Page {
        let start: UInt64
        let data: Data
    }

    static func version(url: URL) -> Version? {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { return nil }
        return Version(value)
    }

    static func page(url: URL, version: Version, offset: UInt64? = nil,
        before: UInt64? = nil, limit: Int) -> Page? {
        stableRead(url: url) { handle, current in
            guard current == version else { return nil }
            let end = min(before ?? current.size, current.size)
            let start = offset ?? (end > UInt64(limit) ? end - UInt64(limit) : 0)
            guard start <= end else { return nil }
            try handle.seek(toOffset: start)
            let count = Int(min(UInt64(limit), end - start))
            let data = try handle.read(upToCount: count) ?? Data()
            guard data.count == count else { return nil }
            return Page(start: start, data: data)
        }
    }

    static func inspect<Value>(url: URL, limit: Int = tailLimit,
        parse: (Data, Data) throws -> Value?) -> Value? {
        stableRead(url: url) { handle, version in
            let size = version.size
            guard size > 0 else { return nil }
            let header = try handle.read(upToCount: 64 * 1024) ?? Data()
            let start = size > UInt64(limit) ? size - UInt64(limit) : 0
            try handle.seek(toOffset: start)
            var data = try handle.read(upToCount: limit) ?? Data()
            guard data.count == Int(size - start), data.last == 10 else { return nil }
            if start > 0 {
                guard let newline = data.firstIndex(of: 10) else { return nil }
                data = Data(data.suffix(from: data.index(after: newline)))
            }
            return try parse(header, data)
        }
    }

    private static func stableRead<Value>(url: URL,
        read: (FileHandle, Version) throws -> Value?) -> Value? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            var before = stat()
            guard fstat(handle.fileDescriptor, &before) == 0 else { return nil }
            let initial = Version(before)
            guard let value = try read(handle, initial),
                  version(url: url) == initial,
                  try handle.seekToEnd() == initial.size else { return nil }
            return value
        } catch { return nil }
    }
}

final class SessionLogLocator {
    enum Naming { case rollout, session }
    private let roots: [URL]
    private let naming: Naming
    private var paths: [String: URL] = [:]
    private var missing: [String: TimeInterval] = [:]

    init(roots: [URL], naming: Naming) { self.roots = roots; self.naming = naming }

    func resolve(_ session: String) -> URL? {
        guard UUID(uuidString: session) != nil else { return nil }
        if let url = paths[session], FileManager.default.fileExists(atPath: url.path) { return url }
        let now = ProcessInfo.processInfo.systemUptime
        if let checked = missing[session], now - checked < 30 { return nil }
        var found: URL?
        var count = 0
        for root in roots {
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in files {
                if naming == .session, url.lastPathComponent == "subagents" {
                    files.skipDescendants()
                    continue
                }
                count += 1
                guard count <= 50_000 else { return nil }
                let matches = naming == .rollout
                    ? url.lastPathComponent.hasSuffix("-\(session).jsonl")
                    : url.lastPathComponent == "\(session).jsonl"
                guard matches else { continue }
                guard found == nil else { return nil }
                found = url
            }
        }
        if paths.count >= 128 { paths.removeAll() }
        if missing.count >= 128 { missing.removeAll() }
        if let found { paths[session] = found } else { missing[session] = now }
        return found
    }
}
