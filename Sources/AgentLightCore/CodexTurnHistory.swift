import Foundation

public struct CodexTurnEvidence: Sendable {
    public let closedTurns: Set<String>
    public let endedAt: Double

    public init(closedTurns: Set<String>, endedAt: Double) {
        self.closedTurns = closedTurns
        self.endedAt = endedAt
    }
}

/// Extracts lifecycle metadata from a bounded local rollout tail.
public final class CodexTurnHistory: @unchecked Sendable {
    public static let shared = CodexTurnHistory()
    private let locator: SessionLogLocator
    private let tailLimit: Int
    private let lock = NSLock()

    public init(home: URL? = nil, tailLimit: Int? = nil) {
        let codex = home ?? ProcessInfo.processInfo.environment["CODEX_HOME"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex")
        locator = SessionLogLocator(roots: [codex.appending(path: "sessions"),
            codex.appending(path: "archived_sessions")], naming: .rollout)
        self.tailLimit = max(1024, tailLimit ?? SessionLogSnapshot.tailLimit)
    }

    public func completion(sessionID: String, turnID: String, beganAt: Double) -> CodexTurnEvidence? {
        lock.withLock {
            guard UUID(uuidString: sessionID) != nil, !turnID.isEmpty,
                  let url = locator.resolve(sessionID) else { return nil }
            return SessionLogSnapshot.inspect(url: url, limit: tailLimit) { header, data in
                guard let newline = header.firstIndex(of: 10),
                      let meta = try? JSONDecoder().decode(Envelope.self, from: header.prefix(upTo: newline)),
                      meta.type == "session_meta", meta.payload.id == sessionID else { return nil }
                var open: Set<String> = []
                var closed: Set<String> = []
                var matchingEnd: Double?
                var lastTime: Double = 0
                var lastWasEnd = false
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let decoder = JSONDecoder()
                for line in data.split(separator: 10) {
                    let event = try decoder.decode(Envelope.self, from: Data(line))
                    guard event.type == "event_msg" else { continue }
                    guard let kind = event.payload.type else { return nil }
                    let relevant = ["task_started", "task_complete", "turn_aborted"].contains(kind)
                    if !relevant {
                        // Unknown lifecycle schemas cannot establish that work has ended.
                        if kind.hasPrefix("task_") || kind.hasPrefix("turn_") { return nil }
                        continue
                    }
                    guard let turn = event.payload.turnID, !turn.isEmpty,
                          let timestamp = event.timestamp,
                          let date = formatter.date(from: timestamp), date.timeIntervalSince1970 >= lastTime else { return nil }
                    lastTime = date.timeIntervalSince1970
                    if kind == "task_started" {
                        open.insert(turn)
                        closed.remove(turn)
                        if turn == turnID { matchingEnd = nil }
                        lastWasEnd = false
                    } else {
                        open.remove(turn)
                        closed.insert(turn)
                        if turn == turnID { matchingEnd = lastTime }
                        lastWasEnd = true
                    }
                }
                guard open.isEmpty, lastWasEnd,
                      let matchingEnd, matchingEnd >= beganAt else { return nil }
                return CodexTurnEvidence(closedTurns: closed, endedAt: lastTime)
            }
        }
    }

    private struct Envelope: Decodable {
        let type: String
        let timestamp: String?
        let payload: Metadata
    }

    private struct Metadata: Decodable {
        let type: String?
        let id: String?
        let turnID: String?
        enum CodingKeys: String, CodingKey {
            case type, id
            case turnID = "turn_id"
        }
    }
}
