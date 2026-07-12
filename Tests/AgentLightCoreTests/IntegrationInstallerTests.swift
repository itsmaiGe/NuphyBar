import Foundation
import Testing
@testable import AgentLightCore

@Test("Codex install enables hooks and preserves notify plus existing hooks")
func codexInstallPreservesConfiguration() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let codex = home.appending(path: ".codex", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
    let config = "notify = [\"existing-notifier\"]\n\n[features]\nmemories = false\n"
    try Data(config.utf8).write(to: codex.appending(path: "config.toml"))
    let existing: [String: Any] = [
        "hooks": ["Stop": [["hooks": [["type": "command", "command": "existing-stop"]]]]]
    ]
    try JSONSerialization.data(withJSONObject: existing).write(to: codex.appending(path: "hooks.json"))

    let installer = IntegrationInstaller(homeURL: home, helperPath: "/Applications/AgentLight.app/Contents/Helpers/agent-light")
    try installer.install(.codex)

    let updatedConfig = try String(contentsOf: codex.appending(path: "config.toml"), encoding: .utf8)
    #expect(updatedConfig.contains("notify = [\"existing-notifier\"]"))
    #expect(updatedConfig.contains("hooks = true"))
    let root = try json(at: codex.appending(path: "hooks.json"))
    let hooks = try #require(root["hooks"] as? [String: Any])
    let stop = try #require(hooks["Stop"] as? [[String: Any]])
    #expect(stop.count == 2)
    #expect(hooks["UserPromptSubmit"] != nil)
    #expect(hooks["PermissionRequest"] != nil)
}

@Test("Claude install and uninstall preserve unrelated settings and hooks")
func claudeInstallIsSurgical() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let claude = home.appending(path: ".claude", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
    let existing: [String: Any] = [
        "env": ["KEEP": "yes"],
        "hooks": ["Stop": [["hooks": [["type": "command", "command": "existing-stop"]]]]]
    ]
    try JSONSerialization.data(withJSONObject: existing).write(to: claude.appending(path: "settings.json"))
    let installer = IntegrationInstaller(homeURL: home, helperPath: "/Applications/AgentLight.app/Contents/Helpers/agent-light")

    try installer.install(.claudeCode)
    #expect(installer.isInstalled(.claudeCode))
    try installer.uninstall(.claudeCode)

    let root = try json(at: claude.appending(path: "settings.json"))
    #expect((root["env"] as? [String: String])?["KEEP"] == "yes")
    let hooks = try #require(root["hooks"] as? [String: Any])
    let stop = try #require(hooks["Stop"] as? [[String: Any]])
    #expect(stop.count == 1)
}

@Test("OpenCode uses an isolated global plugin file")
func openCodePlugin() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let installer = IntegrationInstaller(homeURL: home, helperPath: "/Applications/AgentLight.app/Contents/Helpers/agent-light")

    try installer.install(.openCode)

    let plugin = home.appending(path: ".config/opencode/plugins/agent-light.js")
    let source = try String(contentsOf: plugin, encoding: .utf8)
    #expect(source.contains("session.status"))
    #expect(source.contains("permission.asked"))
    #expect(source.contains("agent-light"))
}

private func temporaryHome() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func json(at url: URL) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}
