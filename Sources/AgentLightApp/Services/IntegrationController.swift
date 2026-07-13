import AgentLightCore
import Foundation

enum IntegrationStatus: Sendable, Equatable {
    case unavailable
    case available
    case needsReview
    case installed
}

actor IntegrationController {
    private let installer: IntegrationInstaller
    private let homeURL = FileManager.default.homeDirectoryForCurrentUser

    init(helperPath: String) {
        let installer = IntegrationInstaller(helperPath: helperPath)
        self.installer = installer
        try? installer.migrateLegacyArtifacts()
    }

    func statuses() -> [AgentProvider: IntegrationStatus] {
        Dictionary(uniqueKeysWithValues: AgentProvider.allCases.map { provider in
            if installer.isInstalled(provider) {
                return (provider, installer.isReady(provider) ? .installed : .needsReview)
            }
            return (provider, isAvailable(provider) ? .available : .unavailable)
        })
    }

    func setInstalled(_ installed: Bool, provider: AgentProvider) throws {
        if installed {
            try installer.install(provider)
        } else {
            try installer.uninstall(provider)
        }
    }

    private func isAvailable(_ provider: AgentProvider) -> Bool {
        switch provider {
        case .codex:
            return FileManager.default.fileExists(atPath: homeURL.appending(path: ".codex").path)
        case .claudeCode:
            return FileManager.default.fileExists(atPath: homeURL.appending(path: ".claude").path)
        case .openCode:
            let paths = [
                homeURL.appending(path: ".config/opencode").path,
                "/opt/homebrew/bin/opencode",
                "/usr/local/bin/opencode",
            ]
            return paths.contains { FileManager.default.fileExists(atPath: $0) }
        case .grokBuild:
            return FileManager.default.fileExists(atPath: homeURL.appending(path: ".grok").path)
        case .hermes:
            let paths = [
                homeURL.appending(path: ".hermes").path,
                homeURL.appending(path: ".local/bin/hermes").path,
                "/opt/homebrew/bin/hermes",
                "/usr/local/bin/hermes",
            ]
            return paths.contains { FileManager.default.fileExists(atPath: $0) }
        case .openClaw:
            let paths = [
                homeURL.appending(path: ".openclaw").path,
                homeURL.appending(path: ".local/bin/openclaw").path,
                "/opt/homebrew/bin/openclaw",
                "/usr/local/bin/openclaw",
            ]
            return paths.contains { FileManager.default.fileExists(atPath: $0) }
        }
    }
}
