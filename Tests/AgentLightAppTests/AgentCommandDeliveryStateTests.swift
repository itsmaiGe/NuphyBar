import AgentLightCore
import Testing
@testable import AgentLightApp

@Test("reconnecting invalidates the last delivered keyboard state")
func reconnectingReplaysTheCurrentState() {
    var delivery = AgentCommandDeliveryState()

    #expect(delivery.shouldSend(.working))
    delivery.markDelivered(.working)
    #expect(!delivery.shouldSend(.working))

    delivery.connectionRestored()

    #expect(delivery.shouldSend(.working))
}

@Test("a failed delivery waits for the HID session to recover")
func failedDeliveryWaitsForRecovery() {
    var delivery = AgentCommandDeliveryState()

    #expect(delivery.shouldSend(.waiting))
    delivery.markFailed()

    #expect(!delivery.shouldSend(.waiting))

    delivery.connectionRestored()

    #expect(delivery.shouldSend(.waiting))
}

@Test("state changes during a HID send are coalesced into one follow-up refresh")
func stateChangesDuringSendAreCoalesced() {
    var activity = AgentDeliveryActivity()

    let began = activity.begin()
    #expect(began)
    activity.requestRefresh()
    activity.requestRefresh()

    let shouldRefresh = activity.finish()
    #expect(shouldRefresh)
    #expect(!activity.isSending)
}

@Test("a completed HID send does not refresh without a new state event")
func completedSendWithoutStateChangeDoesNotRefresh() {
    var activity = AgentDeliveryActivity()

    let began = activity.begin()
    let shouldRefresh = activity.finish()
    #expect(began)
    #expect(!shouldRefresh)
}
