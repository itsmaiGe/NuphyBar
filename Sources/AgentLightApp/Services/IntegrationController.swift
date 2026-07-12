import AgentLightCore
import Foundation

enum IntegrationStatus: Sendable {
    case unavailable
    case available
    case installed
}

actor IntegrationController {
    private let installer: IntegrationInstaller
    private let homeURL = FileManager.default.homeDirectoryForCurrentUser

    init(helperPath: String) {
        installer = IntegrationInstaller(helperPath: helperPath)
    }

    func statuses() -> [AgentProvider: IntegrationStatus] {
        Dictionary(uniqueKeysWithValues: AgentProvider.allCases.map { provider in
            if installer.isInstalled(provider) { return (provider, .installed) }
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
        }
    }
}

