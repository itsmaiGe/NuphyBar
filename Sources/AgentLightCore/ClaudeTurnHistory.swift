import Foundation

public struct ClaudeTurnEvidence: Sendable {
    public let endedAt: Double
    public let status: AgentSessionStatus

    public init(endedAt: Double, status: AgentSessionStatus) {
        self.endedAt = endedAt
        self.status = status
    }
}

public final class ClaudeTurnHistory: @unchecked Sendable {
    public static let shared = ClaudeTurnHistory()
    private let locator: SessionLogLocator
    private let limit: Int
    private let lock = NSLock()
    private var scans: [String: Scan] = [:]

    public init(home: URL? = nil, tailLimit: Int? = nil) {
        let claude = home ?? ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")
        locator = SessionLogLocator(roots: [claude.appending(path: "projects")], naming: .session)
        limit = max(1024, tailLimit ?? SessionLogSnapshot.tailLimit)
    }

    public func completion(sessionID: String, transcriptPath: String?, notBefore: Double) -> ClaudeTurnEvidence? {
        lock.withLock {
            guard UUID(uuidString: sessionID) != nil else { return nil }
            if let transcriptPath, !transcriptPath.hasPrefix("/") { return nil }
            let hinted = transcriptPath.map { URL(fileURLWithPath: $0) }
            if let hinted, (!hinted.path.hasPrefix("/") || hinted.lastPathComponent != "\(sessionID).jsonl"
                || hinted.pathComponents.contains("subagents")) { return nil }
            guard let url = hinted ?? locator.resolve(sessionID) else { return nil }
            guard let version = SessionLogSnapshot.version(url: url), version.size > 0 else {
                scans.removeValue(forKey: sessionID)
                return nil
            }
            var scan = scans[sessionID].flatMap { $0.version == version && $0.path == url.path ? $0 : nil }
                ?? Scan(version: version, path: url.path)
            if !scan.finished {
                guard let page = SessionLogSnapshot.page(url: url, version: version,
                    offset: scan.cursor, before: scan.cursor == nil ? scan.before : nil, limit: limit) else {
                    scans.removeValue(forKey: sessionID)
                    return nil
                }
                do {
                    if scan.cursor == nil {
                        if let root = Self.latestRoot(in: page, sessionID: sessionID) {
                            scan.cursor = page.start + UInt64(root)
                            try scan.consume(Data(page.data.dropFirst(root)), sessionID: sessionID)
                        } else {
                            let next = page.start + UInt64(page.data.firstIndex(of: 10).map { $0 + 1 } ?? 0)
                            scan.before = next < scan.before ? next : page.start
                            if page.start == 0 { scan.finished = true }
                        }
                    } else {
                        try scan.consume(page.data, sessionID: sessionID)
                    }
                } catch {
                    scan.parser = Parser()
                    scan.finished = true
                }
                guard SessionLogSnapshot.version(url: url) == version else {
                    scans.removeValue(forKey: sessionID)
                    return nil
                }
                if scans[sessionID] == nil, scans.count >= 128 { scans.removeAll() }
                scans[sessionID] = scan
            }
            guard scan.finished, scan.parser.pendingDequeue == nil,
                  let proof = scan.parser.ending, proof.endedAt >= notBefore else { return nil }
            return proof
        }
    }

    private static func latestRoot(in page: SessionLogSnapshot.Page, sessionID: String) -> Int? {
        let decoder = JSONDecoder()
        var start = page.start == 0 ? 0 : page.data.firstIndex(of: 10).map { $0 + 1 } ?? page.data.count
        var root: Int?
        for end in page.data.indices where end >= start && page.data[end] == 10 {
            if let event = try? decoder.decode(Entry.self, from: page.data.subdata(in: start..<end)),
               event.type == "user", event.isSidechain != true, event.sessionId == sessionID,
               !event.isTranscriptNotification, event.uuid != nil, let message = event.message,
               message.toolResults.isEmpty {
                root = start
            }
            start = end + 1
        }
        return root
    }

    private struct Scan {
        let version: SessionLogSnapshot.Version
        let path: String
        var before: UInt64
        var cursor: UInt64?
        var finished = false
        var skippingLine = false
        var parser = Parser()

        init(version: SessionLogSnapshot.Version, path: String) {
            self.version = version
            self.path = path
            before = version.size
        }

        mutating func consume(_ data: Data, sessionID: String) throws {
            guard var position = cursor else { return }
            var body = data
            if skippingLine {
                if let end = body.firstIndex(of: 10) {
                    position += UInt64(end + 1)
                    body = Data(body.dropFirst(end + 1))
                    skippingLine = false
                } else {
                    cursor = position + UInt64(body.count)
                    finished = cursor == version.size
                    return
                }
            }
            if let last = body.lastIndex(of: 10) {
                let count = last + 1
                try parser.consume(Data(body.prefix(count)), sessionID: sessionID)
                cursor = position + UInt64(count)
                if position + UInt64(body.count) == version.size, count < body.count {
                    parser.ending = nil
                    finished = true
                } else { finished = cursor == version.size }
            } else if !body.isEmpty {
                // An oversized or incomplete record cannot establish completion.
                parser = Parser()
                skippingLine = true
                cursor = position + UInt64(body.count)
                finished = cursor == version.size
            } else {
                cursor = position
                finished = position == version.size
            }
        }
    }

    private enum InvalidRecord: Error { case identity, metadata }

    private struct Parser {
        var chain: Set<String> = []
        var tools: Set<String> = []
        var latestActivity: Double = 0
        var ending: ClaudeTurnEvidence?
        var pendingDequeue: Double?

        mutating func consume(_ data: Data, sessionID: String) throws {
            let decoder = JSONDecoder()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            for line in data.split(separator: 10) {
                let event = try decoder.decode(Entry.self, from: Data(line))
                if let dequeue = pendingDequeue {
                    pendingDequeue = nil
                    if event.isTranscriptNotification, event.isSidechain == false, event.sessionId == sessionID,
                       let parent = event.parentUuid, chain.contains(parent), let uuid = event.uuid {
                        chain.insert(uuid)
                        continue
                    }
                    ending = nil
                    latestActivity = max(latestActivity, dequeue)
                }
                guard event.isSidechain != true else { continue }
                switch event.type {
                case "assistant", "user", "attachment", "api-request", "api-request-blob", "api-request-shape", "queue-operation":
                    guard event.sessionId == sessionID else { throw InvalidRecord.identity }
                default:
                    if ["last-prompt", "ai-title", "atis-latch", "file-history-snapshot"].contains(event.type) { continue }
                    if event.type == "system", ["turn_duration", "stop_hook_summary", "hook_progress", "informational", "api_error"]
                        .contains(event.subtype ?? "") {
                        guard event.sessionId == sessionID else { throw InvalidRecord.identity }
                        if event.subtype == "informational" || event.subtype == "api_error" {
                            ending = nil
                            guard let timestamp = event.timestamp, let date = formatter.date(from: timestamp) else {
                                throw InvalidRecord.metadata
                            }
                            latestActivity = max(latestActivity, date.timeIntervalSince1970)
                        }
                        if let parent = event.parentUuid, let uuid = event.uuid, chain.contains(parent) {
                            chain.insert(uuid)
                        }
                        continue
                    }
                    ending = nil
                    continue
                }
                if event.type == "api-request-blob" {
                    ending = nil
                    continue
                }
                guard let timestamp = event.timestamp, let date = formatter.date(from: timestamp) else { throw InvalidRecord.metadata }
                let time = date.timeIntervalSince1970
                if ending != nil, event.type == "queue-operation", event.operation == "dequeue" {
                    // The next record distinguishes a transcript notification from a queued request.
                    pendingDequeue = time
                    continue
                }
                ending = nil
                if event.type == "attachment" {
                    if let parent = event.parentUuid, let uuid = event.uuid, chain.contains(parent) {
                        chain.insert(uuid)
                    } else { chain = []; tools = [] }
                    // Response attachments can be logged after the response timestamp.
                    // Their chain position matters; they do not start another request.
                    continue
                }
                if event.type == "api-request" || event.type == "api-request-shape" || event.type == "queue-operation" {
                    latestActivity = max(latestActivity, time)
                    continue
                }
                guard let uuid = event.uuid, let message = event.message else { throw InvalidRecord.metadata }
                if event.type == "user" {
                    let results = message.toolResults
                    if results.isEmpty {
                        chain = [uuid]
                        tools = []
                    } else {
                        guard let parent = event.parentUuid, chain.contains(parent) else {
                            chain = []; tools = []
                            latestActivity = max(latestActivity, time)
                            continue
                        }
                        chain.insert(uuid)
                        for result in results {
                            guard let id = result.toolUseID else { throw InvalidRecord.metadata }
                            tools.remove(id)
                        }
                    }
                    latestActivity = max(latestActivity, time)
                    continue
                }
                guard let parent = event.parentUuid, chain.contains(parent),
                      let blocks = message.blocks else {
                    chain = []; tools = []
                    latestActivity = max(latestActivity, time)
                    continue
                }
                chain.insert(uuid)
                for block in blocks where block.type == "tool_use" {
                    guard let id = block.id else { throw InvalidRecord.metadata }
                    tools.insert(id)
                }
                if time >= latestActivity, tools.isEmpty,
                   !blocks.contains(where: { $0.type == "tool_use" }) {
                    if event.isApiErrorMessage == true,
                       ["stop_sequence", "end_turn"].contains(message.stopReason ?? "") {
                        ending = ClaudeTurnEvidence(endedAt: time, status: .error)
                    } else if event.isApiErrorMessage != true, message.stopReason == "end_turn" {
                        ending = ClaudeTurnEvidence(endedAt: time, status: .complete)
                    }
                }
                latestActivity = max(latestActivity, time)
            }
        }
    }

    private struct Entry: Decodable {
        let type: String
        let timestamp: String?
        let sessionId: String?
        let uuid: String?
        let parentUuid: String?
        let subtype: String?
        let isSidechain: Bool?
        let isApiErrorMessage: Bool?
        let message: Message?
        let operation: String?
        let isTranscriptNotification: Bool

        private struct Origin: Decodable {
            let kind: String?
        }

        enum CodingKeys: String, CodingKey {
            case type, timestamp, sessionId, uuid, parentUuid, subtype, isSidechain, isApiErrorMessage, message
            case operation, queueTranscriptOnly, origin, promptSource
        }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            type = try values.decode(String.self, forKey: .type)
            timestamp = try values.decodeIfPresent(String.self, forKey: .timestamp)
            sessionId = try values.decodeIfPresent(String.self, forKey: .sessionId)
            uuid = try values.decodeIfPresent(String.self, forKey: .uuid)
            parentUuid = try values.decodeIfPresent(String.self, forKey: .parentUuid)
            subtype = try values.decodeIfPresent(String.self, forKey: .subtype)
            isSidechain = try values.decodeIfPresent(Bool.self, forKey: .isSidechain)
            isApiErrorMessage = try values.decodeIfPresent(Bool.self, forKey: .isApiErrorMessage)
            message = ["assistant", "user"].contains(type)
                ? try values.decodeIfPresent(Message.self, forKey: .message) : nil
            operation = type == "queue-operation" ? try values.decodeIfPresent(String.self, forKey: .operation) : nil
            isTranscriptNotification = type == "user"
                && message?.toolResults.isEmpty == true
                && (try? values.decode(Bool.self, forKey: .queueTranscriptOnly)) == true
                && (try? values.decode(String.self, forKey: .promptSource)) == "system"
                && (try? values.decode(Origin.self, forKey: .origin))?.kind == "task-notification"
        }
    }

    private struct Message: Decodable {
        let stopReason: String?
        let blocks: [Block]?
        var toolResults: [Block] { blocks?.filter { $0.type == "tool_result" } ?? [] }
        enum CodingKeys: String, CodingKey { case stopReason = "stop_reason"; case content }
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            stopReason = try container.decodeIfPresent(String.self, forKey: .stopReason)
            if var contents = try? container.nestedUnkeyedContainer(forKey: .content) {
                var values: [Block] = []
                while !contents.isAtEnd { values.append(try contents.decode(Block.self)) }
                blocks = values
            } else { blocks = nil }
        }
    }

    private struct Block: Decodable {
        let type: String
        let id: String?
        let toolUseID: String?
        enum CodingKeys: String, CodingKey { case type, id; case toolUseID = "tool_use_id" }
    }
}
