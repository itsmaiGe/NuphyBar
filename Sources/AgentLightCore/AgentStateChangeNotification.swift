import CDarwinNotify
import Dispatch

enum AgentStateChangeNotificationError: Error {
    case registrationFailed(UInt32)
}

public enum AgentStateChangeNotification {
    fileprivate static let name = "com.maige.NuphyBar.agent-state-changed"

    @discardableResult
    static func post() -> Bool {
        name.withCString { notify_post($0) == NOTIFY_STATUS_OK }
    }

    public static func observe(
        on queue: DispatchQueue = .main,
        _ handler: @escaping @Sendable () -> Void
    ) throws -> AgentStateChangeObservation {
        try AgentStateChangeObservation(queue: queue, handler: handler)
    }
}

public final class AgentStateChangeObservation: @unchecked Sendable {
    private var token: Int32 = -1

    fileprivate init(
        queue: DispatchQueue,
        handler: @escaping @Sendable () -> Void
    ) throws {
        let status = AgentStateChangeNotification.name.withCString {
            notify_register_dispatch($0, &token, queue) { _ in handler() }
        }
        guard status == NOTIFY_STATUS_OK else {
            throw AgentStateChangeNotificationError.registrationFailed(status)
        }
    }

    deinit {
        if token >= 0 {
            notify_cancel(token)
        }
    }
}
