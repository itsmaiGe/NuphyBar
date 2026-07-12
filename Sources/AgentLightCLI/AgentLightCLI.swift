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
            }
        } catch {
            fputs("agentlight: \(error)\n", stderr)
            exit(1)
        }
    }
}
