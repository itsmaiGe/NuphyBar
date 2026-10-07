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
                RecoveryDiagnostics.shared.record("hook.received", fields: [
                    "provider": provider.rawValue, "event": eventName,
                ])
                let payload = FileHandle.standardInput.readDataToEndOfFile()
                if let event = try HookEventMapper.map(
                    provider: provider,
                    eventName: eventName,
                    payload: payload
                ) {
                    try recordAgentEvent(event)
                }
                if let response = HookEventMapper.response(provider: provider, eventName: eventName) {
                    FileHandle.standardOutput.write(response + Data("\n".utf8))
                }
            case .event(let event):
                try recordAgentEvent(event)
            }
        } catch {
            RecoveryDiagnostics.shared.record("helper.failed", fields: ["error": String(describing: type(of: error))])
            fputs("agent-light: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func recordAgentEvent(_ event: AgentEvent) throws {
        // Hooks only persist state. The menu app owns HID access and sends the report.
        _ = try AgentStateFile().record(
            event,
            now: Int64(Date().timeIntervalSince1970)
        )
        RecoveryDiagnostics.shared.record("state.persisted", fields: [
            "provider": event.provider.rawValue,
            "session": RecoveryDiagnostics.anonymousID(event.sessionID),
            "turn": event.turnID.map(RecoveryDiagnostics.anonymousID) ?? "unavailable",
            "status": String(describing: event.status),
        ])
    }
}
