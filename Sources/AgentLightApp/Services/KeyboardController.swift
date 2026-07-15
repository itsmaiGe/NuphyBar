import AgentLightCore
import AgentLightHID

actor KeyboardController {
    private let transport = NuPhyHIDTransport()

    func connectionStates() -> AsyncStream<NuPhyHIDConnectionState> {
        transport.connectionStates
    }

    func refresh() {
        transport.refresh()
    }

    func send(_ command: AgentLightCommand) throws {
        try transport.send(command)
    }
}
