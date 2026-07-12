import Foundation

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
                "UserPromptSubmit", "PermissionRequest", "Stop",
            ])
        case .claudeCode:
            try mergeHooks(at: claudeSettingsURL, provider: provider, events: [
                "UserPromptSubmit", "PermissionRequest", "Notification", "Stop", "SessionEnd",
            ])
        case .openCode:
            try writeOpenCodePlugin()
        }
    }

    public func uninstall(_ provider: AgentProvider) throws {
        switch provider {
        case .codex: try removeHooks(at: codexHooksURL, provider: provider)
        case .claudeCode: try removeHooks(at: claudeSettingsURL, provider: provider)
        case .openCode:
            let url = openCodePluginURL
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    public func isInstalled(_ provider: AgentProvider) -> Bool {
        switch provider {
        case .codex: return jsonContainsMarker(at: codexHooksURL, provider: provider)
        case .claudeCode: return jsonContainsMarker(at: claudeSettingsURL, provider: provider)
        case .openCode:
            return (try? String(contentsOf: openCodePluginURL, encoding: .utf8))?
                .contains("Installed by Agent Light") == true
        }
    }

    private var codexHooksURL: URL { homeURL.appending(path: ".codex/hooks.json") }
    private var codexConfigURL: URL { homeURL.appending(path: ".codex/config.toml") }
    private var claudeSettingsURL: URL { homeURL.appending(path: ".claude/settings.json") }
    private var openCodePluginURL: URL {
        homeURL.appending(path: ".config/opencode/plugins/agent-light.js")
    }

    private func command(provider: AgentProvider, event: String) -> String {
        "\(shellQuote(helperPath)) hook \(provider.rawValue) \(event)"
    }

    private func mergeHooks(at url: URL, provider: AgentProvider, events: [String]) throws {
        var root = try readJSONObject(at: url)
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.removeAll { groupContainsMarker($0, provider: provider) }
            groups.append([
                "hooks": [[
                    "type": "command",
                    "command": command(provider: provider, event: event),
                    "timeout": 10,
                ]],
            ])
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
            groups.removeAll { groupContainsMarker($0, provider: provider) }
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

    private func jsonContainsMarker(at url: URL, provider: AgentProvider) -> Bool {
        guard let root = try? readJSONObject(at: url),
              let hooks = root["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            (value as? [[String: Any]])?.contains {
                groupContainsMarker($0, provider: provider)
            } == true
        }
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
        let helper = jsString(helperPath)
        let source = """
        // Installed by Agent Light. OpenCode loads global plugins from this directory.
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
        try writeData(Data(source.utf8), to: openCodePluginURL)
    }

    private func readJSONObject(at url: URL) throws -> [String: Any] {
        let url = resolvedURL(url)
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try writeData(data + Data("\n".utf8), to: resolvedURL(url))
    }

    private func writeData(_ data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let existed = fileManager.fileExists(atPath: url.path)
        let permissions = existed
            ? (try? fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
            : nil
        let backup = URL(fileURLWithPath: url.path + ".agent-light-backup")
        if existed && !fileManager.fileExists(atPath: backup.path) {
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
}
