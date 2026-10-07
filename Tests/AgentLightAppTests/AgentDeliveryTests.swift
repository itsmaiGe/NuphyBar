import AgentLightCore
import AgentLightHID
import Foundation
import Testing
@testable import AgentLightApp

private func readyDelivery() -> AgentCommandDeliveryState {
    var delivery = AgentCommandDeliveryState()
    delivery.connect(HIDConnectionIdentity(sessionID: UUID(), deviceID: 1))
    delivery.update(command: .working, revision: 1)
    return delivery
}

private func begin(_ delivery: inout AgentCommandDeliveryState) throws -> AgentDeliveryAttempt {
    let attempt = delivery.begin()
    return try #require(attempt)
}

@Test("duplicate agent events do not resend the same command on a healthy connection")
func duplicateEventsDoNotSend() throws {
    var delivery = readyDelivery()
    let first = try begin(&delivery)
    delivery.finish(first, succeeded: true)
    delivery.update(command: .working, revision: 2)
    #expect(delivery.begin() == nil)
}

@Test("a new connection replays unchanged state")
func reconnectReplaysState() throws {
    var delivery = readyDelivery()
    let first = try begin(&delivery)
    delivery.finish(first, succeeded: true)
    delivery.connect(HIDConnectionIdentity(sessionID: UUID(), deviceID: 1))
    #expect(delivery.begin()?.target.command == .working)
}

@Test("completion while offline restores idle instead of yesterday's work")
func offlineCompletionRestoresIdle() throws {
    var delivery = readyDelivery()
    let first = try begin(&delivery)
    delivery.finish(first, succeeded: true)
    delivery.connect(nil)
    delivery.update(command: .complete, revision: 2)
    delivery.update(command: .idle, revision: 2)
    #expect(delivery.begin() == nil)
    delivery.connect(HIDConnectionIdentity(sessionID: UUID(), deviceID: 1))
    #expect(delivery.begin()?.target.command == .idle)
}

@Test("old send results cannot suppress replay or fail a replacement connection", arguments: [true, false])
func staleSendResults(succeeded: Bool) throws {
    var delivery = readyDelivery()
    let old = try begin(&delivery)
    delivery.connect(HIDConnectionIdentity(sessionID: UUID(), deviceID: 1))
    #expect(delivery.begin() == nil)
    let accepted = delivery.finish(old, succeeded: succeeded)
    #expect(!accepted)
    #expect(delivery.accepted == nil)
    #expect(delivery.begin() != nil)
}

@Test("only the latest target is sent after in-flight state changes")
func inFlightUpdatesCoalesce() throws {
    var delivery = readyDelivery()
    let first = try begin(&delivery)
    delivery.update(command: .waiting, revision: 2)
    delivery.update(command: .idle, revision: 3)
    #expect(delivery.begin() == nil)
    let accepted = delivery.finish(first, succeeded: true)
    #expect(!accepted)
    #expect(delivery.begin()?.target.command == .idle)
}

@Test("a failed connection waits for recovery rather than retrying every notification")
func failureWaitsForRecovery() throws {
    var delivery = readyDelivery()
    let first = try begin(&delivery)
    delivery.finish(first, succeeded: false)
    delivery.update(command: .waiting, revision: 2)
    #expect(delivery.begin() == nil)
    delivery.connect(HIDConnectionIdentity(sessionID: UUID(), deviceID: 1))
    #expect(delivery.begin()?.target.command == .waiting)
}

@Test("AULA can explicitly refresh an accepted command without concurrent sends")
func explicitKeepalive() throws {
    var delivery = readyDelivery()
    let first = try begin(&delivery)
    #expect(delivery.begin(force: true) == nil)
    delivery.finish(first, succeeded: true)
    #expect(delivery.begin(force: true) != nil)
}

@Test("USB renewals keep every active state alive for hours without overlapping sends", arguments: [
    AgentLightCommand.working, .toolRunning, .outputting, .waiting,
])
func usbActiveStateRenewal(command: AgentLightCommand) throws {
    var delivery = readyDelivery()
    delivery.update(command: command, revision: 1)
    let initial = delivery.begin(now: 0)
    var attempt = try #require(initial)
    delivery.finish(attempt, succeeded: true, now: 0)
    for minute in 1...120 {
        let time = Double(minute * 60)
        let next = delivery.begin(refreshInterval: 300, now: time)
        if minute.isMultiple(of: 5) {
            attempt = try #require(next)
            #expect(attempt.target.command == command)
            #expect(delivery.begin(refreshInterval: 300, now: time) == nil)
            delivery.finish(attempt, succeeded: true, now: time)
        } else {
            #expect(next == nil)
        }
    }
}

@Test("periodic renewal never repeats idle or terminal states", arguments: [
    AgentLightCommand.idle, .complete, .error,
])
func usbTerminalStatesAreNotRenewed(command: AgentLightCommand) throws {
    var delivery = readyDelivery()
    delivery.update(command: command, revision: 1)
    let initial = delivery.begin(now: 0)
    let first = try #require(initial)
    delivery.finish(first, succeeded: true, now: 0)
    #expect(delivery.begin(refreshInterval: 300, now: 3600) == nil)
}

@Test("Bluetooth does not receive a periodic renewal")
func bluetoothStaysChangeDriven() throws {
    var delivery = readyDelivery()
    let initial = delivery.begin(now: 0)
    let first = try #require(initial)
    delivery.finish(first, succeeded: true, now: 0)
    #expect(delivery.begin(now: 3600) == nil)
}
