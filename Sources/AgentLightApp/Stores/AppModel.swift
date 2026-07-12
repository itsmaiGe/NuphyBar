import AgentLightCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var preferences: AgentLightPreferences
    var connectionText = "正在检查键盘…"
    var isConnected = false
    var isSending = false
    var lastError: String?
    var integrationStatuses: [AgentProvider: IntegrationStatus] = [:]

    private let preferencesFile = AgentLightPreferencesFile()
    private let keyboard = KeyboardController()
    private let integrations: IntegrationController

    init() {
        let helperPath = Bundle.main.bundleURL
            .appending(path: "Contents/Helpers/agent-light")
            .path
        integrations = IntegrationController(helperPath: helperPath)
        preferences = (try? preferencesFile.load()) ?? AgentLightPreferences()
        refreshConnection(applyPreferences: true)
        refreshIntegrations()
    }

    func saveAndApplyPreferences() {
        do {
            try preferencesFile.save(preferences)
        } catch {
            lastError = "无法保存设置：\(error.localizedDescription)"
            return
        }

        perform {
            try await self.keyboard.apply(self.preferences)
        }
    }

    func send(_ command: AgentLightCommand) {
        perform {
            try await self.keyboard.send(command)
        }
    }

    func refreshConnection(applyPreferences: Bool = false) {
        Task {
            do {
                _ = try await keyboard.describe()
                isConnected = true
                connectionText = "Air60 V2 · 蓝牙已连接"
                lastError = nil
                if applyPreferences {
                    try await keyboard.apply(preferences)
                }
            } catch {
                isConnected = false
                connectionText = "未找到 Air60 V2"
                lastError = error.localizedDescription
            }
        }
    }

    func refreshIntegrations() {
        Task {
            integrationStatuses = await integrations.statuses()
        }
    }

    func toggleIntegration(_ provider: AgentProvider) {
        let shouldInstall = integrationStatuses[provider] != .installed
        Task {
            do {
                try await integrations.setInstalled(shouldInstall, provider: provider)
                integrationStatuses = await integrations.statuses()
                lastError = nil
            } catch {
                lastError = "接入失败：\(error.localizedDescription)"
            }
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isSending else { return }
        isSending = true
        lastError = nil
        Task {
            defer { isSending = false }
            do {
                try await operation()
                isConnected = true
                connectionText = "Air60 V2 · 蓝牙已连接"
            } catch {
                isConnected = false
                connectionText = "发送失败"
                lastError = error.localizedDescription
            }
        }
    }
}
