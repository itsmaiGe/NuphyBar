import AgentLightCore
import AgentLightHID
import AppKit
import Foundation
import Observation
import OSLog

private let hidLogger = Logger(subsystem: "com.maige.NuphyBar", category: "HID")

@MainActor
@Observable
final class AppModel {
    var keyboardModel: String?
    var isConnected = false
    var keyboardError: String?
    var integrationError: String?
    var integrationStatuses: [AgentProvider: IntegrationStatus] = [:]
    var hidAccessState: NuPhyHIDAccessState = .unknown
    var integrationNoticeProvider: AgentProvider?

    private let keyboard = KeyboardController()
    private let integrations: IntegrationController
    @ObservationIgnored private var deliveryState = AgentCommandDeliveryState()
    @ObservationIgnored private var agentMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var connectionMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var integrationNoticeTask: Task<Void, Never>?
    @ObservationIgnored private var isRefreshingConnection = false
    @ObservationIgnored private var isSending = false

    init() {
        let helperPath = Bundle.main.bundleURL
            .appending(path: "Contents/Helpers/agent-light")
            .path
        integrations = IntegrationController(helperPath: helperPath)
        refreshConnection()
        refreshIntegrations()
        startAgentMonitor()
        startConnectionMonitor()
    }

    func refreshConnection() {
        hidAccessState = NuPhyHIDTransport.accessState
        guard hidAccessState == .granted else {
            isConnected = false
            keyboardModel = nil
            keyboardError = nil
            return
        }
        guard !isRefreshingConnection else { return }
        isRefreshingConnection = true

        Task {
            defer { isRefreshingConnection = false }
            do {
                let productName = try await keyboard.productName()
                let wasConnected = isConnected
                keyboardModel = productName
                isConnected = true
                keyboardError = nil
                if !wasConnected {
                    deliveryState.connectionRestored()
                    hidLogger.info("NuPhy Bluetooth keyboard connection is ready")
                    applyAgentStateIfChanged()
                }
            } catch {
                isConnected = false
                keyboardModel = nil
                keyboardError = error.localizedDescription
                hidLogger.error("NuPhy keyboard connection check failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func requestHIDAccess() {
        _ = NuPhyHIDTransport.requestAccess()
        hidAccessState = NuPhyHIDTransport.accessState

        if hidAccessState == .granted {
            refreshConnection()
        } else {
            openInputMonitoringSettings()
        }
    }

    func openInputMonitoringSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func refreshIntegrations() {
        Task {
            integrationStatuses = await integrations.statuses()
        }
    }

    func toggleIntegration(_ provider: AgentProvider) {
        let shouldInstall = integrationStatuses[provider] == .available
        Task {
            do {
                try await integrations.setInstalled(shouldInstall, provider: provider)
                integrationStatuses = await integrations.statuses()
                showIntegrationNotice(for: provider)
                integrationError = nil
            } catch {
                integrationError = "接入失败：\(error.localizedDescription)"
            }
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isSending else { return }
        isSending = true
        keyboardError = nil
        Task {
            defer { isSending = false }
            do {
                try await operation()
                isConnected = true
            } catch {
                isConnected = false
                deliveryState.markFailed()
                keyboardError = error.localizedDescription
                hidLogger.error("Keyboard state send failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func startAgentMonitor() {
        agentMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.applyAgentStateIfChanged()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func startConnectionMonitor() {
        connectionMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshConnection()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func applyAgentStateIfChanged() {
        guard hidAccessState == .granted, isConnected, !isSending,
              var state = try? AgentStateFile().load() else { return }
        let command = state.displayCommand(now: Int64(Date().timeIntervalSince1970))
        guard deliveryState.shouldSend(command) else { return }

        perform {
            try await self.keyboard.send(command)
            self.deliveryState.markDelivered(command)
        }
    }

    private func showIntegrationNotice(for provider: AgentProvider) {
        integrationNoticeProvider = provider
        integrationNoticeTask?.cancel()
        integrationNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.integrationNoticeProvider = nil
        }
    }
}

struct AgentCommandDeliveryState {
    private var lastDeliveredCommand: AgentLightCommand?

    func shouldSend(_ command: AgentLightCommand) -> Bool {
        command != lastDeliveredCommand
    }

    mutating func markDelivered(_ command: AgentLightCommand) {
        lastDeliveredCommand = command
    }

    mutating func markFailed() {
        lastDeliveredCommand = nil
    }

    mutating func connectionRestored() {
        lastDeliveredCommand = nil
    }
}
