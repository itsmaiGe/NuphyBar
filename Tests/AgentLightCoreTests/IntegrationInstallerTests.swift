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
    #expect(hooks["PostToolUse"] != nil)
}

@Test("installing a new app replaces hooks that point to an older app copy")
func installMigratesOldAppPath() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let codex = home.appending(path: ".codex", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
    let oldCommand = "'/tmp/old/AgentLight.app/Contents/Helpers/agent-light' hook codex Stop"
    let existing: [String: Any] = [
        "hooks": ["Stop": [["hooks": [["type": "command", "command": oldCommand]]]]]
    ]
    try JSONSerialization.data(withJSONObject: existing).write(to: codex.appending(path: "hooks.json"))

    let newPath = "/Users/me/Applications/AgentLight.app/Contents/Helpers/agent-light"
    let installer = IntegrationInstaller(homeURL: home, helperPath: newPath)
    try installer.install(.codex)

    let root = try json(at: codex.appending(path: "hooks.json"))
    let hooks = try #require(root["hooks"] as? [String: Any])
    let stop = try #require(hooks["Stop"] as? [[String: Any]])
    let handlers = stop.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
    let commands = handlers.compactMap { $0["command"] as? String }
    #expect(commands.count == 1)
    #expect(commands[0].contains(newPath))
    #expect(!commands[0].contains("/tmp/old"))
}

@Test("installing the same integration twice remains idempotent")
func repeatedInstallDoesNotDuplicateHooks() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let helper = "/Users/me/Applications/NuphyBar.app/Contents/Helpers/agent-light"
    let installer = IntegrationInstaller(homeURL: home, helperPath: helper)

    try installer.install(.codex)
    try installer.install(.codex)

    let root = try json(at: home.appending(path: ".codex/hooks.json"))
    let hooks = try #require(root["hooks"] as? [String: Any])
    let stop = try #require(hooks["Stop"] as? [[String: Any]])
    let commands = stop
        .flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
        .compactMap { $0["command"] as? String }
    #expect(commands.count == 1)
    #expect(commands[0].contains(helper))
}

@Test("Codex integration remains pending until every installed hook is trusted")
func codexIntegrationRequiresHookTrust() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let helper = "/Users/me/Applications/NuphyBar.app/Contents/Helpers/agent-light"
    let installer = IntegrationInstaller(homeURL: home, helperPath: helper)

    try installer.install(.codex)

    #expect(installer.isInstalled(.codex))
    #expect(!installer.isReady(.codex))
}

@Test("Codex integration is ready after all installed hooks are trusted")
func codexIntegrationRecognizesTrustedHooks() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let helper = "/Users/me/Applications/NuphyBar.app/Contents/Helpers/agent-light"
    let installer = IntegrationInstaller(homeURL: home, helperPath: helper)

    try installer.install(.codex)
    let hooksPath = home.appending(path: ".codex/hooks.json").path
    let config = """
    [features]
    hooks = true

    [hooks.state."\(hooksPath):user_prompt_submit:0:0"]
    trusted_hash = "sha256:one"

    [hooks.state."\(hooksPath):permission_request:0:0"]
    trusted_hash = "sha256:two"

    [hooks.state."\(hooksPath):post_tool_use:0:0"]
    trusted_hash = "sha256:three"

    [hooks.state."\(hooksPath):stop:0:0"]
    trusted_hash = "sha256:four"
    """
    try Data(config.utf8).write(to: home.appending(path: ".codex/config.toml"))

    #expect(installer.isReady(.codex))
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

    let installed = try json(at: claude.appending(path: "settings.json"))
    let installedHooks = try #require(installed["hooks"] as? [String: Any])
    #expect(installedHooks["PostToolUse"] != nil)
    let notificationGroups = try #require(installedHooks["Notification"] as? [[String: Any]])
    #expect(notificationGroups.contains { $0["matcher"] as? String == "agent_needs_input|elicitation_dialog" })

    try installer.uninstall(.claudeCode)

    let root = try json(at: claude.appending(path: "settings.json"))
    #expect((root["env"] as? [String: String])?["KEEP"] == "yes")
    let hooks = try #require(root["hooks"] as? [String: Any])
    let stop = try #require(hooks["Stop"] as? [[String: Any]])
    #expect(stop.count == 1)
}

@Test("OpenCode uses an owned plugin file without replacing a user plugin")
func openCodePluginIsNonDestructive() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let installer = IntegrationInstaller(homeURL: home, helperPath: "/Applications/AgentLight.app/Contents/Helpers/agent-light")
    let plugins = home.appending(path: ".config/opencode/plugins", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
    let userPlugin = plugins.appending(path: "agent-light.js")
    try Data("export const UserPlugin = true\n".utf8).write(to: userPlugin)

    try installer.install(.openCode)

    let plugin = plugins.appending(path: "nuphybar.js")
    let source = try String(contentsOf: plugin, encoding: .utf8)
    #expect(source.contains("session.status"))
    #expect(source.contains("permission.asked"))
    #expect(source.contains("agent-light"))
    #expect(try String(contentsOf: userPlugin, encoding: .utf8) == "export const UserPlugin = true\n")

    try installer.uninstall(.openCode)

    #expect(!FileManager.default.fileExists(atPath: plugin.path))
    #expect(try String(contentsOf: userPlugin, encoding: .utf8) == "export const UserPlugin = true\n")
}

@Test("OpenCode migration restores a plugin overwritten by the old installer")
func openCodePluginMigrationRestoresBackup() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let plugins = home.appending(path: ".config/opencode/plugins", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
    let legacyPlugin = plugins.appending(path: "agent-light.js")
    let backup = plugins.appending(path: "agent-light.js.agent-light-backup")
    try Data("// Installed by NuphyBar\n".utf8).write(to: legacyPlugin)
    try Data("export const UserPlugin = true\n".utf8).write(to: backup)
    let installer = IntegrationInstaller(homeURL: home, helperPath: "/Applications/NuphyBar.app/Contents/Helpers/agent-light")

    try installer.install(.openCode)

    #expect(try String(contentsOf: legacyPlugin, encoding: .utf8) == "export const UserPlugin = true\n")
    #expect(!FileManager.default.fileExists(atPath: backup.path))
    #expect(FileManager.default.fileExists(atPath: plugins.appending(path: "nuphybar.js").path))
}

@Test("a valid JSON file with the wrong root shape is never overwritten")
func invalidConfigurationShapeIsPreserved() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let claude = home.appending(path: ".claude", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
    let settings = claude.appending(path: "settings.json")
    let original = Data("[\"keep-me\"]\n".utf8)
    try original.write(to: settings)
    let installer = IntegrationInstaller(homeURL: home, helperPath: "/Applications/NuphyBar.app/Contents/Helpers/agent-light")

    var didRejectInvalidShape = false
    do {
        try installer.install(.claudeCode)
    } catch {
        didRejectInvalidShape = true
    }

    #expect(didRejectInvalidShape)
    #expect(try Data(contentsOf: settings) == original)
}

@Test("Grok Build installs a personal hook file with lifecycle events")
func grokBuildUsesNativePersonalHooks() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let helper = "/Applications/NuphyBar.app/Contents/Helpers/agent-light"
    let installer = IntegrationInstaller(homeURL: home, helperPath: helper)

    try installer.install(.grokBuild)

    let hookURL = home.appending(path: ".grok/hooks/nuphybar.json")
    let root = try json(at: hookURL)
    let hooks = try #require(root["hooks"] as? [String: Any])
    #expect(hooks["UserPromptSubmit"] != nil)
    #expect(hooks["Stop"] != nil)
    #expect(hooks["StopFailure"] != nil)
    #expect(installer.isInstalled(.grokBuild))

    try installer.uninstall(.grokBuild)
    #expect(!FileManager.default.fileExists(atPath: hookURL.path))
}

@Test("Grok Build never overwrites a user hook with the same filename")
func grokBuildPreservesConflictingUserHook() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let hook = home.appending(path: ".grok/hooks/nuphybar.json")
    try FileManager.default.createDirectory(at: hook.deletingLastPathComponent(), withIntermediateDirectories: true)
    let original = Data(#"{"user":"keep"}"#.utf8)
    try original.write(to: hook)
    let installer = IntegrationInstaller(homeURL: home, helperPath: "/Applications/NuphyBar.app/Contents/Helpers/agent-light")

    #expect(throws: IntegrationInstallerError.self) {
        try installer.install(.grokBuild)
    }
    #expect(try Data(contentsOf: hook) == original)
}

@Test("Hermes integration writes an enabled lifecycle plugin")
func hermesUsesLifecyclePlugin() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let installer = IntegrationInstaller(
        homeURL: home,
        helperPath: "/Applications/NuphyBar.app/Contents/Helpers/agent-light"
    )

    try installer.install(.hermes)

    let plugin = home.appending(path: ".hermes/plugins/nuphybar/__init__.py")
    let source = try String(contentsOf: plugin, encoding: .utf8)
    #expect(source.contains("pre_llm_call"))
    #expect(source.contains("pre_approval_request"))
    #expect(source.contains("on_session_finalize"))
    let config = try String(contentsOf: home.appending(path: ".hermes/config.yaml"), encoding: .utf8)
    #expect(config.contains("- nuphybar"))
    #expect(installer.isInstalled(.hermes))
}

@Test("Hermes removal only edits its plugins enabled list")
func hermesRemovalPreservesUnrelatedYamlLists() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let hermes = home.appending(path: ".hermes", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: hermes, withIntermediateDirectories: true)
    let original = """
    unrelated:
      - nuphybar
    plugins:
      enabled:
        - existing-plugin
        - nuphybar
    """
    try Data(original.utf8).write(to: hermes.appending(path: "config.yaml"))
    let installer = IntegrationInstaller(homeURL: home, helperPath: "/Applications/NuphyBar.app/Contents/Helpers/agent-light")
    try installer.install(.hermes)
    try installer.uninstall(.hermes)

    let updated = try String(contentsOf: hermes.appending(path: "config.yaml"), encoding: .utf8)
    #expect(updated.contains("unrelated:\n  - nuphybar"))
    #expect(updated.contains("- existing-plugin"))
    let pluginsSection = try #require(updated.components(separatedBy: "plugins:").last)
    #expect(!pluginsSection.contains("- nuphybar"))
}

@Test("OpenClaw hook install is enabled through its official CLI")
func openClawUsesManagedHookCLI() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let binaryDirectory = home.appending(path: ".openclaw/bin", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: binaryDirectory, withIntermediateDirectories: true)
    let binary = binaryDirectory.appending(path: "openclaw")
    let script = "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$(dirname \"$0\")/calls\"\n"
    try Data(script.utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    let installer = IntegrationInstaller(homeURL: home, helperPath: "/Applications/NuphyBar.app/Contents/Helpers/agent-light")

    try installer.install(.openClaw)
    #expect(installer.isInstalled(.openClaw))
    let handler = try String(contentsOf: home.appending(path: ".openclaw/hooks/nuphybar/handler.js"), encoding: .utf8)
    #expect(handler.contains("message"))
    #expect(handler.contains("[\"event\", \"openclaw\""))

    try installer.uninstall(.openClaw)
    let calls = try String(contentsOf: binaryDirectory.appending(path: "calls"), encoding: .utf8)
    #expect(calls.contains("hooks enable nuphybar"))
    #expect(calls.contains("hooks disable nuphybar"))
}

@Test("Antigravity installs an isolated official global plugin")
func antigravityUsesGlobalPluginHooks() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let helper = "/Applications/NuphyBar.app/Contents/Helpers/agent-light"
    let installer = IntegrationInstaller(homeURL: home, helperPath: helper)

    try installer.install(.antigravity)

    let plugin = home.appending(path: ".gemini/config/plugins/nuphybar")
    let manifest = try json(at: plugin.appending(path: "plugin.json"))
    #expect(manifest["name"] as? String == "nuphybar")
    #expect((manifest["description"] as? String)?.contains("NuphyBar") == true)

    let hooks = try json(at: plugin.appending(path: "hooks.json"))
    let integration = try #require(hooks["nuphybar"] as? [String: Any])
    #expect(integration["PreInvocation"] != nil)
    #expect(integration["Stop"] != nil)
    #expect(installer.isInstalled(.antigravity))

    try installer.uninstall(.antigravity)
    #expect(!FileManager.default.fileExists(atPath: plugin.path))
}

@Test("Antigravity never overwrites an existing plugin directory")
func antigravityPreservesConflictingPlugin() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let plugin = home.appending(path: ".gemini/config/plugins/nuphybar")
    try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
    let manifest = plugin.appending(path: "plugin.json")
    let original = Data(#"{"name":"user-owned"}"#.utf8)
    try original.write(to: manifest)
    let installer = IntegrationInstaller(
        homeURL: home,
        helperPath: "/Applications/NuphyBar.app/Contents/Helpers/agent-light"
    )

    #expect(throws: IntegrationInstallerError.self) {
        try installer.install(.antigravity)
    }
    #expect(try Data(contentsOf: manifest) == original)
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
