import Foundation

public struct RGBColor: Codable, Equatable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var hexString: String {
        String(format: "%02X%02X%02X", red, green, blue)
    }
}

public struct AgentLightPreferences: Codable, Equatable, Sendable {
    public var color: RGBColor
    public var brightness: Double
    public var completionDuration: UInt8

    public init(
        color: RGBColor = RGBColor(red: 0, green: 160, blue: 255),
        brightness: Double = 1,
        completionDuration: UInt8 = 10
    ) {
        self.color = color
        self.brightness = min(max(brightness, 0.1), 1)
        self.completionDuration = min(max(completionDuration, 3), 60)
    }

    public var effectiveColor: RGBColor {
        RGBColor(
            red: UInt8((Double(color.red) * brightness).rounded()),
            green: UInt8((Double(color.green) * brightness).rounded()),
            blue: UInt8((Double(color.blue) * brightness).rounded())
        )
    }
}

public struct AgentLightPreferencesFile: Sendable {
    public static var defaultURL: URL {
        AgentStateFile.defaultURL.deletingLastPathComponent().appending(path: "settings.json")
    }

    public let url: URL

    public init(url: URL = Self.defaultURL) {
        self.url = url
    }

    public func load() throws -> AgentLightPreferences {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AgentLightPreferences()
        }
        return try JSONDecoder().decode(AgentLightPreferences.self, from: Data(contentsOf: url))
    }

    public func save(_ preferences: AgentLightPreferences) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(preferences).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
