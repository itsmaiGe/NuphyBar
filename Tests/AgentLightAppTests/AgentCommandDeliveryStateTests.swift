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
