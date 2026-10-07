import AgentLightCore
import AgentLightHID

protocol KeyboardControlling: Sendable {
    func connectionStates() async -> AsyncStream<NuPhyHIDConnectionState>
    func refresh() async
    func rebuildSession() async
    func send(_ command: AgentLightCommand, connection: HIDConnectionIdentity) async throws
}

actor KeyboardController: KeyboardControlling {
    private let transport = NuPhyHIDTransport()

    func connectionStates() -> AsyncStream<NuPhyHIDConnectionState> {
        transport.connectionStates
    }

    func refresh() {
        transport.refresh()
    }

    func rebuildSession() {
        transport.rebuildSession()
    }

    func send(_ command: AgentLightCommand, connection: HIDConnectionIdentity) throws {
        try transport.send(command, expectedConnection: connection)
    }
}
