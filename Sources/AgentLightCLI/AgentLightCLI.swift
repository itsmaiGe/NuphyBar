import AgentLightCore
import AgentLightHID
import Darwin
import Foundation

@main
struct AgentLightCLI {
    static func main() {
        do {
            let request = try CommandLineRequest.parse(Array(CommandLine.arguments.dropFirst()))
            let transport = Air60HIDTransport()

            switch request {
            case .describe:
                print(try transport.describe())
            case .send(let command):
                try transport.send(command)
            case .hook(let provider, let eventName):
                let payload = FileHandle.standardInput.readDataToEndOfFile()
                guard let event = try? HookEventMapper.map(
                    provider: provider,
                    eventName: eventName,
                    payload: payload
                ) else { return }
                sendAgentEvent(event, transport: transport)
            case .event(let event):
                sendAgentEvent(event, transport: transport)
            }
        } catch {
            fputs("agentlight: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func sendAgentEvent(_ event: AgentEvent, transport: Air60HIDTransport) {
        // Lifecycle hooks must never block or fail the agent when the keyboard is off.
        guard let command = try? AgentStateFile().apply(
            event,
            now: Int64(Date().timeIntervalSince1970)
        ) else { return }
        try? transport.send(command)
    }
}
