import Foundation
import Testing
@testable import AgentLightCore

@Test("brightness scales the selected RGB color without changing the selection")
func effectiveColor() {
    let preferences = AgentLightPreferences(
        color: RGBColor(red: 12, green: 34, blue: 56),
        brightness: 0.5,
        completionDuration: 10
    )

    #expect(preferences.effectiveColor == RGBColor(red: 6, green: 17, blue: 28))
    #expect(preferences.color == RGBColor(red: 12, green: 34, blue: 56))
}

@Test("preferences persist for the menu app and short-lived hook helper")
func preferencesPersistence() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let file = AgentLightPreferencesFile(url: directory.appending(path: "settings.json"))
    defer { try? FileManager.default.removeItem(at: directory) }

    let value = AgentLightPreferences(
        color: RGBColor(red: 90, green: 80, blue: 70),
        brightness: 0.75,
        completionDuration: 14
    )
    try file.save(value)

    #expect(try file.load() == value)
}
