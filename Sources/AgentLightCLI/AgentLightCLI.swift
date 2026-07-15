import AgentLightCore
import AgentLightHID
import Darwin
import Foundation

@main
struct AgentLightCLI {
    static func main() {
        do {
            let request = try CommandLineRequest.parse(Array(CommandLine.arguments.dropFirst()))

            switch request {
            case .describe:
                print(try NuPhyHIDTransport().describe())
            case .send(let command):
                try NuPhyHIDTransport().send(command)
            case .hook(let provider, let eventName):
                let payload = FileHandle.standardInput.readDataToEndOfFile()
                if let event = try? HookEventMapper.map(
                    provider: provider,
                    eventName: eventName,
                    payload: payload
                ) {
                    recordAgentEvent(event)
                }
                if let response = HookEventMapper.response(provider: provider, eventName: eventName) {
                    FileHandle.standardOutput.write(response + Data("\n".utf8))
                }
            case .event(let event):
                recordAgentEvent(event)
            }
        } catch {
            fputs("agent-light: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func recordAgentEvent(_ event: AgentEvent) {
        // Hooks only persist state. The menu app owns HID access and sends the report.
        _ = try? AgentStateFile().apply(
            event,
            now: Int64(Date().timeIntervalSince1970)
        )
    }
}
