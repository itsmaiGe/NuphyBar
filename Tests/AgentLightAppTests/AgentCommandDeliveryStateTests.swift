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

@Test("a failed delivery is eligible for retry")
func failedDeliveryCanRetry() {
    var delivery = AgentCommandDeliveryState()

    #expect(delivery.shouldSend(.waiting))
    delivery.markFailed()

    #expect(delivery.shouldSend(.waiting))
}
