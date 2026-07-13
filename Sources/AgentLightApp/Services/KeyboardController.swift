import AgentLightCore
import AgentLightHID

actor KeyboardController {
    private let transport = NuPhyHIDTransport()

    func productName() throws -> String {
        try transport.connectedProductName()
    }

    func send(_ command: AgentLightCommand) throws {
        try transport.send(command)
    }
}
