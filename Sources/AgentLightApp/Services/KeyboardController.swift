import AgentLightCore
import AgentLightHID

actor KeyboardController {
    private let transport = Air60HIDTransport()

    func describe() throws -> String {
        try transport.describe()
    }

    func send(_ command: AgentLightCommand) throws {
        try transport.send(command)
    }

    func apply(_ preferences: AgentLightPreferences) throws {
        let color = preferences.effectiveColor
        try transport.send(.color(red: color.red, green: color.green, blue: color.blue))
        try transport.send(.completionDuration(seconds: preferences.completionDuration))
    }
}

