import AgentLightCore
import AgentLightHID
import Foundation

struct AgentDeliveryTarget: Equatable {
    let command: AgentLightCommand
    let revision: UInt64
}

struct AgentDeliveryAttempt: Equatable {
    let id = UUID()
    let connection: HIDConnectionIdentity
    let target: AgentDeliveryTarget
}

struct AgentCommandDeliveryState {
    private(set) var connection: HIDConnectionIdentity?
    private(set) var target: AgentDeliveryTarget?
    private(set) var inFlight: AgentDeliveryAttempt?
    private(set) var accepted: AgentDeliveryAttempt?
    private var acceptedAt: TimeInterval?
    private var failedConnection: HIDConnectionIdentity?

    mutating func connect(_ identity: HIDConnectionIdentity?) {
        guard connection != identity else { return }
        connection = identity
        accepted = nil
        acceptedAt = nil
        failedConnection = nil
    }

    mutating func update(command: AgentLightCommand, revision: UInt64) {
        target = AgentDeliveryTarget(command: command, revision: revision)
    }

    mutating func begin(force: Bool = false, refreshInterval: TimeInterval? = nil,
                        now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> AgentDeliveryAttempt? {
        guard inFlight == nil, let connection, let target, connection != failedConnection else { return nil }
        let isActive: Bool = switch target.command {
        case .working, .toolRunning, .outputting, .waiting: true
        case .idle, .complete, .error: false
        }
        let refreshDue = isActive && refreshInterval.map { interval in
            acceptedAt.map { now - $0 >= interval } ?? false
        } == true
        if !force, !refreshDue, accepted?.connection == connection, accepted?.target.command == target.command {
            return nil
        }
        let attempt = AgentDeliveryAttempt(connection: connection, target: target)
        inFlight = attempt
        return attempt
    }

    @discardableResult
    mutating func finish(_ attempt: AgentDeliveryAttempt, succeeded: Bool,
                         now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard inFlight == attempt else { return false }
        inFlight = nil
        guard connection == attempt.connection else { return false }
        if !succeeded {
            failedConnection = attempt.connection
            accepted = nil
            acceptedAt = nil
            return true
        }
        guard target == attempt.target else { return false }
        accepted = attempt
        acceptedAt = now
        return true
    }
}
