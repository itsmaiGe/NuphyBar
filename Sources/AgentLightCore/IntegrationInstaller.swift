import Foundation

public enum IntegrationInstallerError: LocalizedError {
    case openCodePluginConflict
    case invalidConfigurationRoot
    case integrationFileConflict(String)
    case agentExecutableNotFound(String)
    case agentCommandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openCodePluginConflict:
            return "OpenCode 已存在同名 nuphybar.js 插件，NuphyBar 未覆盖该文件"
        case .invalidConfigurationRoot:
            return "Agent 配置文件必须是 JSON 对象，NuphyBar 未修改该文件"
        case let .integrationFileConflict(name):
            return "\(name) 已存在同名接入文件，NuphyBar 未覆盖该文件"
        case let .agentExecutableNotFound(name):
            return "找不到 \(name) 命令，无法启用接入"
        case let .agentCommandFailed(name):
            return "\(name) 未能启用 NuphyBar 接入"
        }
    }
}

public struct IntegrationInstaller: Sendable {
    public let homeURL: URL
    public let helperPath: String

    public init(
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        helperPath: String
    ) {
        self.homeURL = homeURL
        self.helperPath = helperPath
    }

    public func install(_ provider: AgentProvider) throws {
        switch provider {
        case .codex:
            try enableCodexHooksFeature()
            try mergeHooks(at: codexHooksURL, provider: provider, events: [
                "UserPromptSubmit", "PermissionRequest", "PostToolUse", "Stop",
            ])
        case .claudeCode:
            try mergeHooks(at: claudeSettingsURL, provider: provider, events: [
                "UserPromptSubmit", "PermissionRequest", "PostToolUse", "Notification", "Stop", "SessionEnd",
            ], matchers: ["Notification": "agent_needs_input|elicitation_dialog"])
        case .openCode:
            try writeOpenCodePlugin()
        case .grokBuild:
            try writeGrokHooks()
        case .hermes:
            try writeHermesPlugin()
            try setHermesPluginEnabled(true)
        case .openClaw:
            try writeOpenClawHook()
            do {
                try runOpenClaw(["hooks", "enable", "nuphybar"])
            } catch {
                try? removeOwnedDirectory(at: openClawHookURL, markerFile: "HOOK.md")
                throw error
            }
        case .antigravity:
            try writeAntigravityPlugin()
        }
    }

    public func uninstall(_ provider: AgentProvider) throws {
        switch provider {
        case .codex: try removeHooks(at: codexHooksURL, provider: provider)
        case .claudeCode: try removeHooks(at: claudeSettingsURL, provider: provider)
        case .openCode:
            try removeOwnedOpenCodePlugin(at: openCodePluginURL)
            try restoreLegacyOpenCodePlugin()
        case .grokBuild:
            try removeOwnedFile(at: grokHooksURL, marker: "NuphyBar")
        case .hermes:
            try removeOwnedDirectory(at: hermesPluginURL, markerFile: "plugin.yaml")
            try setHermesPluginEnabled(false)
        case .openClaw:
            try? runOpenClaw(["hooks", "disable", "nuphybar"])
            try removeOwnedDirectory(at: openClawHookURL, markerFile: "HOOK.md")
        case .antigravity:
            try removeOwnedDirectory(at: antigravityPluginURL, markerFile: "plugin.json")
        }
    }

    public func isInstalled(_ provider: AgentProvider) -> Bool {
        switch provider {
        case .codex: return jsonContainsMarker(at: codexHooksURL, provider: provider)
        case .claudeCode: return jsonContainsMarker(at: claudeSettingsURL, provider: provider)
        case .openCode:
            return isOwnedOpenCodePlugin(at: openCodePluginURL)
                || isOwnedOpenCodePlugin(at: legacyOpenCodePluginURL)
        case .grokBuild:
            return fileContainsMarker(at: grokHooksURL, marker: "NuphyBar")
        case .hermes:
            return fileContainsMarker(at: hermesPluginURL.appending(path: "plugin.yaml"), marker: "NuphyBar")
                && hermesConfigContainsPlugin()
        case .openClaw:
            return fileContainsMarker(at: openClawHookURL.appending(path: "HOOK.md"), marker: "NuphyBar")
        case .antigravity:
            return fileContainsMarker(
                at: antigravityPluginURL.appending(path: "plugin.json"),
                marker: "NuphyBar"
            ) && fileContainsMarker(
                at: antigravityPluginURL.appending(path: "hooks.json"),
                marker: "hook antigravity"
            )
        }
    }

    public func isReady(_ provider: AgentProvider) -> Bool {
        guard isInstalled(provider) else { return false }
        guard provider == .codex else { return true }

        let keys = codexHookTrustKeys()
        guard keys.count == 4,
              let config = try? String(contentsOf: resolvedURL(codexConfigURL), encoding: .utf8)
        else { return false }
        return keys.allSatisfy { configContainsTrustedHook($0, config: config) }
    }

    public func migrateLegacyArtifacts() throws {
        guard isOwnedOpenCodePlugin(at: legacyOpenCodePluginURL) else { return }
        try writeOpenCodePlugin()
    }

    private var codexHooksURL: URL { homeURL.appending(path: ".codex/hooks.json") }
    private var codexConfigURL: URL { homeURL.appending(path: ".codex/config.toml") }
    private var claudeSettingsURL: URL { homeURL.appending(path: ".claude/settings.json") }
    private var openCodePluginURL: URL {
        homeURL.appending(path: ".config/opencode/plugins/nuphybar.js")
    }
    private var legacyOpenCodePluginURL: URL {
        homeURL.appending(path: ".config/opencode/plugins/agent-light.js")
    }
    private var grokHooksURL: URL { homeURL.appending(path: ".grok/hooks/nuphybar.json") }
    private var hermesPluginURL: URL { homeURL.appending(path: ".hermes/plugins/nuphybar") }
    private var hermesConfigURL: URL { homeURL.appending(path: ".hermes/config.yaml") }
    private var openClawHookURL: URL { homeURL.appending(path: ".openclaw/hooks/nuphybar") }
    private var antigravityPluginURL: URL {
        homeURL.appending(path: ".gemini/config/plugins/nuphybar")
    }

    private func writeAntigravityPlugin() throws {
        let manifestURL = antigravityPluginURL.appending(path: "plugin.json")
        if FileManager.default.fileExists(atPath: resolvedURL(antigravityPluginURL).path),
           !fileContainsMarker(at: manifestURL, marker: "NuphyBar") {
            throw IntegrationInstallerError.integrationFileConflict("Antigravity 插件")
        }

        let manifest: [String: Any] = [
            "$schema": "https://antigravity.google/schemas/v1/plugin.json",
            "name": "nuphybar",
            "description": "NuphyBar local keyboard status integration",
        ]
        let hook: (String) -> [String: Any] = { event in
            [
                "type": "command",
                "command": command(provider: .antigravity, event: event),
                "timeout": 10,
            ]
        }
        let hooks: [String: Any] = [
            "nuphybar": [
                "PreInvocation": [hook("PreInvocation")],
                "Stop": [hook("Stop")],
            ],
        ]
        try writeJSONObject(manifest, to: manifestURL)
        try writeJSONObject(hooks, to: antigravityPluginURL.appending(path: "hooks.json"))
    }

    private func writeGrokHooks() throws {
        try requireOwnedOrAbsent(grokHooksURL, marker: "NuphyBar", integration: "Grok Build Hook")
        let events = [
            "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
            "PostToolUseFailure", "PermissionDenied", "Stop", "StopFailure", "Notification",
        ]
        let hooks = Dictionary(uniqueKeysWithValues: events.map { event in
            (event, [["hooks": [[
                "type": "command",
                "command": command(provider: .grokBuild, event: event),
                "timeout": 10,
            ]]]])
        })
        let root: [String: Any] = ["_nuphybar": "Installed by NuphyBar", "hooks": hooks]
        try writeJSONObject(root, to: grokHooksURL)
    }

    private func writeHermesPlugin() throws {
        try requireOwnedOrAbsent(
            hermesPluginURL.appending(path: "plugin.yaml"),
            marker: "NuphyBar",
            integration: "Hermes 插件"
        )
        let manifest = """
        name: nuphybar
        version: 1.0.0
        description: NuphyBar local keyboard status integration
        author: NuphyBar
        provides_hooks:
          - pre_llm_call
          - pre_approval_request
          - post_approval_response
          - on_session_finalize
          - on_session_end
        """
        let helper = pythonString(helperPath)
        let source = """
        # Installed by NuphyBar. Sends status only to the local helper.
        import os
        import subprocess

        HELPER = \(helper)

        def _send(status, **kwargs):
            session_id = str(
                kwargs.get("session_id")
                or kwargs.get("session_key")
                or os.environ.get("HERMES_SESSION_ID")
                or "hermes"
            )
            subprocess.Popen(
                [HELPER, "event", "hermes", status, session_id],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )

        def register(ctx):
            ctx.register_hook("pre_llm_call", lambda **kw: _send("working", **kw))
            ctx.register_hook("pre_approval_request", lambda **kw: _send("waiting", **kw))
            ctx.register_hook("post_approval_response", lambda **kw: _send("working", **kw))
            ctx.register_hook("on_session_finalize", lambda **kw: _send("complete", **kw))
            ctx.register_hook("on_session_end", lambda **kw: _send("idle", **kw))
        """
        try writeData(Data(manifest.utf8), to: hermesPluginURL.appending(path: "plugin.yaml"), createBackup: false)
        try writeData(Data(source.utf8), to: hermesPluginURL.appending(path: "__init__.py"), createBackup: false)
    }

    private func writeOpenClawHook() throws {
        try requireOwnedOrAbsent(
            openClawHookURL.appending(path: "HOOK.md"),
            marker: "NuphyBar",
            integration: "OpenClaw Hook"
        )
        let metadata = """
        ---
        name: nuphybar
        description: "NuphyBar local keyboard status integration"
        metadata: { "openclaw": { "events": ["message:received", "message:sent", "command:stop"], "os": ["darwin"] } }
        ---
        # NuphyBar
        Sends coarse agent lifecycle state to the local NuphyBar helper.
        """
        let helper = jsString(helperPath)
        let handler = """
        // Installed by NuphyBar. Sends status only to the local helper.
        import { execFile } from "node:child_process"
        const helper = \(helper)

        export default async function handler(event) {
          const session = String(event.sessionKey ?? event.context?.sessionId ?? "openclaw")
          let status = null
          if (event.type === "message" && event.action === "received") status = "working"
          if (event.type === "message" && event.action === "sent") status = event.context?.success === false ? "error" : "complete"
          if (event.type === "command" && event.action === "stop") status = "idle"
          if (status) execFile(helper, ["event", "openclaw", status, session], () => {})
        }
        """
        try writeData(Data(metadata.utf8), to: openClawHookURL.appending(path: "HOOK.md"), createBackup: false)
        try writeData(Data(handler.utf8), to: openClawHookURL.appending(path: "handler.js"), createBackup: false)
    }

    private func command(provider: AgentProvider, event: String) -> String {
        "\(shellQuote(helperPath)) hook \(provider.rawValue) \(event)"
    }

    private func mergeHooks(
        at url: URL,
        provider: AgentProvider,
        events: [String],
        matchers: [String: String] = [:]
    ) throws {
        var root = try readJSONObject(at: url)
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.removeAll { groupContainsAgentLightMarker($0, provider: provider) }
            var group: [String: Any] = [
                "hooks": [[
                    "type": "command",
                    "command": command(provider: provider, event: event),
                    "timeout": 10,
                ]],
            ]
            if let matcher = matchers[event] {
                group["matcher"] = matcher
            }
            groups.append(group)
            hooks[event] = groups
        }
        root["hooks"] = hooks
        try writeJSONObject(root, to: url)
    }

    private func removeHooks(at url: URL, provider: AgentProvider) throws {
        guard FileManager.default.fileExists(atPath: resolvedURL(url).path) else { return }
        var root = try readJSONObject(at: url)
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for event in Array(hooks.keys) {
            guard var groups = hooks[event] as? [[String: Any]] else { continue }
            groups.removeAll { groupContainsAgentLightMarker($0, provider: provider) }
            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = groups
            }
        }
        root["hooks"] = hooks
        try writeJSONObject(root, to: url)
    }

    private func groupContainsMarker(_ group: [String: Any], provider: AgentProvider) -> Bool {
        let handlers = group["hooks"] as? [[String: Any]] ?? []
        return handlers.contains { handler in
            guard let command = handler["command"] as? String else { return false }
            return command.contains(helperPath) && command.contains("hook \(provider.rawValue)")
        }
    }

    private func groupContainsAgentLightMarker(
        _ group: [String: Any],
        provider: AgentProvider
    ) -> Bool {
        let handlers = group["hooks"] as? [[String: Any]] ?? []
        return handlers.contains { handler in
            guard let command = handler["command"] as? String else { return false }
            return command.contains("/Contents/Helpers/agent-light")
                && command.contains("hook \(provider.rawValue)")
        }
    }

    private func jsonContainsMarker(at url: URL, provider: AgentProvider) -> Bool {
        guard let root = try? readJSONObject(at: url),
              let hooks = root["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            (value as? [[String: Any]])?.contains {
                groupContainsMarker($0, provider: provider)
            } == true
        }
    }

    private func codexHookTrustKeys() -> [String] {
        guard let root = try? readJSONObject(at: codexHooksURL),
              let hooks = root["hooks"] as? [String: Any]
        else { return [] }

        let events = [
            ("UserPromptSubmit", "user_prompt_submit"),
            ("PermissionRequest", "permission_request"),
            ("PostToolUse", "post_tool_use"),
            ("Stop", "stop"),
        ]
        let sourcePath = resolvedURL(codexHooksURL).path
        var keys: [String] = []

        for (event, eventKey) in events {
            let groups = hooks[event] as? [[String: Any]] ?? []
            for (groupIndex, group) in groups.enumerated() {
                let handlers = group["hooks"] as? [[String: Any]] ?? []
                for (handlerIndex, handler) in handlers.enumerated() {
                    guard let command = handler["command"] as? String,
                          command.contains(helperPath),
                          command.contains("hook codex")
                    else { continue }
                    keys.append("\(sourcePath):\(eventKey):\(groupIndex):\(handlerIndex)")
                }
            }
        }
        return keys
    }

    private func configContainsTrustedHook(_ key: String, config: String) -> Bool {
        let escapedKey = key
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let expectedHeader = "[hooks.state.\"\(escapedKey)\"]"
        var isTargetSection = false

        for line in config.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if isTargetSection { return false }
                isTargetSection = trimmed == expectedHeader
            } else if isTargetSection, trimmed.hasPrefix("trusted_hash") {
                let value = trimmed.split(separator: "=", maxSplits: 1)
                    .last?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                return value.hasPrefix("\"sha256:") && value.hasSuffix("\"")
            }
        }
        return false
    }

    private func enableCodexHooksFeature() throws {
        let url = resolvedURL(codexConfigURL)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var lines = existing.components(separatedBy: "\n")

        if let featuresIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[features]" }) {
            let sectionEnd = lines[(featuresIndex + 1)...].firstIndex {
                let line = $0.trimmingCharacters(in: .whitespaces)
                return line.hasPrefix("[") && line.hasSuffix("]")
            } ?? lines.endIndex
            if let hooksIndex = lines[(featuresIndex + 1)..<sectionEnd].firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("hooks =")
            }) {
                lines[hooksIndex] = "hooks = true"
            } else {
                lines.insert("hooks = true", at: featuresIndex + 1)
            }
        } else {
            if !lines.isEmpty && lines.last != "" { lines.append("") }
            lines.append("[features]")
            lines.append("hooks = true")
        }
        try writeData(Data(lines.joined(separator: "\n").utf8), to: url)
    }

    private func writeOpenCodePlugin() throws {
        if FileManager.default.fileExists(atPath: openCodePluginURL.path),
           !isOwnedOpenCodePlugin(at: openCodePluginURL) {
            throw IntegrationInstallerError.openCodePluginConflict
        }

        let helper = jsString(helperPath)
        let source = """
        // Installed by NuphyBar. OpenCode loads global plugins from this directory.
        export const AgentLightPlugin = async ({ $ }) => {
          const helper = \(helper)
          const send = async (status, sessionID) => {
            if (!sessionID) return
            await $`${helper} event opencode ${status} ${sessionID}`.quiet().nothrow()
          }

          return {
            event: async ({ event }) => {
              const properties = event.properties ?? {}
              const sessionID = properties.sessionID
              if (event.type === "session.status") {
                if (properties.status?.type === "busy") await send("working", sessionID)
                if (properties.status?.type === "idle") await send("complete", sessionID)
              } else if (event.type === "session.idle") {
                await send("complete", sessionID)
              } else if (event.type === "session.error") {
                await send("error", sessionID)
              } else if (event.type === "permission.asked") {
                await send("waiting", sessionID)
              } else if (event.type === "permission.replied") {
                await send("working", sessionID)
              }
            },
          }
        }
        """
        try writeData(Data(source.utf8), to: openCodePluginURL, createBackup: false)
        try restoreLegacyOpenCodePlugin()
    }

    private func isOwnedOpenCodePlugin(at url: URL) -> Bool {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return source.contains("Installed by NuphyBar")
            || source.contains("Installed by Agent Light")
    }

    private func removeOwnedOpenCodePlugin(at url: URL) throws {
        guard isOwnedOpenCodePlugin(at: url) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func restoreLegacyOpenCodePlugin() throws {
        guard isOwnedOpenCodePlugin(at: legacyOpenCodePluginURL) else { return }
        let backup = URL(fileURLWithPath: legacyOpenCodePluginURL.path + ".agent-light-backup")
        try FileManager.default.removeItem(at: legacyOpenCodePluginURL)
        if FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.moveItem(at: backup, to: legacyOpenCodePluginURL)
        }
    }

    private func setHermesPluginEnabled(_ enabled: Bool) throws {
        let url = resolvedURL(hermesConfigURL)
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        if !enabled && !fileExists { return }
        var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
            .components(separatedBy: .newlines)
        let normalized = { (line: String) in
            line.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")
        }

        if let pluginsIndex = lines.firstIndex(where: { $0 == "plugins:" }) {
            var sectionEnd = lines[(pluginsIndex + 1)...].firstIndex { line in
                !line.isEmpty && !line.hasPrefix(" ") && !line.hasPrefix("\t")
            } ?? lines.endIndex
            for index in lines.indices.reversed()
                where index > pluginsIndex && index < sectionEnd && normalized(lines[index]) == "- nuphybar" {
                lines.remove(at: index)
            }
            sectionEnd = lines[(pluginsIndex + 1)...].firstIndex { line in
                !line.isEmpty && !line.hasPrefix(" ") && !line.hasPrefix("\t")
            } ?? lines.endIndex

            guard enabled else {
                try writeData(Data(lines.joined(separator: "\n").utf8), to: url)
                return
            }
            if let enabledIndex = lines[(pluginsIndex + 1)..<sectionEnd].firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces) == "enabled:"
            }) {
                lines.insert("    - nuphybar", at: enabledIndex + 1)
            } else {
                lines.insert(contentsOf: ["  enabled:", "    - nuphybar"], at: pluginsIndex + 1)
            }
        } else {
            guard enabled else { return }
            while lines.last == "" { lines.removeLast() }
            if !lines.isEmpty { lines.append("") }
            lines.append(contentsOf: ["plugins:", "  enabled:", "    - nuphybar", ""])
        }
        try writeData(Data(lines.joined(separator: "\n").utf8), to: url)
    }

    private func hermesConfigContainsPlugin() -> Bool {
        guard let config = try? String(contentsOf: resolvedURL(hermesConfigURL), encoding: .utf8) else {
            return false
        }
        return config.components(separatedBy: .newlines).contains { line in
            let value = line.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")
            return value == "- nuphybar"
        }
    }

    private func runOpenClaw(_ arguments: [String]) throws {
        guard let executable = openClawExecutable() else {
            throw IntegrationInstallerError.agentExecutableNotFound("OpenClaw")
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw IntegrationInstallerError.agentCommandFailed("OpenClaw")
        }
    }

    private func openClawExecutable() -> URL? {
        let candidates = [
            homeURL.appending(path: ".openclaw/bin/openclaw"),
            homeURL.appending(path: ".local/bin/openclaw"),
            homeURL.appending(path: ".npm-global/bin/openclaw"),
            URL(fileURLWithPath: "/opt/homebrew/bin/openclaw"),
            URL(fileURLWithPath: "/usr/local/bin/openclaw"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func fileContainsMarker(at url: URL, marker: String) -> Bool {
        guard let source = try? String(contentsOf: resolvedURL(url), encoding: .utf8) else { return false }
        return source.contains(marker)
    }

    private func requireOwnedOrAbsent(_ url: URL, marker: String, integration: String) throws {
        guard FileManager.default.fileExists(atPath: resolvedURL(url).path) else { return }
        guard fileContainsMarker(at: url, marker: marker) else {
            throw IntegrationInstallerError.integrationFileConflict(integration)
        }
    }

    private func removeOwnedFile(at url: URL, marker: String) throws {
        guard fileContainsMarker(at: url, marker: marker) else { return }
        try FileManager.default.removeItem(at: resolvedURL(url))
    }

    private func removeOwnedDirectory(at url: URL, markerFile: String) throws {
        guard fileContainsMarker(at: url.appending(path: markerFile), marker: "NuphyBar") else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func readJSONObject(at url: URL) throws -> [String: Any] {
        let url = resolvedURL(url)
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let root = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any] else {
            throw IntegrationInstallerError.invalidConfigurationRoot
        }
        return root
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try writeData(data + Data("\n".utf8), to: resolvedURL(url))
    }

    private func writeData(_ data: Data, to url: URL, createBackup: Bool = true) throws {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let existed = fileManager.fileExists(atPath: url.path)
        let permissions = existed
            ? (try? fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
            : nil
        let backup = URL(fileURLWithPath: url.path + ".agent-light-backup")
        if createBackup && existed && !fileManager.fileExists(atPath: backup.path) {
            try fileManager.copyItem(at: url, to: backup)
        }

        try data.write(to: url, options: .atomic)
        if let permissions {
            try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }

    private func resolvedURL(_ url: URL) -> URL {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        return values?.isSymbolicLink == true ? url.resolvingSymlinksInPath() : url
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func jsString(_ value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [value])
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }

    private func pythonString(_ value: String) -> String {
        jsString(value)
    }
}
