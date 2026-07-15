import AgentLightCore
import AgentLightHID
import AppKit
import Foundation
import Observation
import OSLog

private let hidLogger = Logger(subsystem: "com.maige.NuphyBar", category: "HID")
private let agentStateLogger = Logger(subsystem: "com.maige.NuphyBar", category: "AgentState")

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
    @ObservationIgnored private var agentStateObservation: AgentStateChangeObservation?
    @ObservationIgnored private var agentExpirationTask: Task<Void, Never>?
    @ObservationIgnored private var agentFallbackTask: Task<Void, Never>?
    @ObservationIgnored private var keyboardConnectionTask: Task<Void, Never>?
    @ObservationIgnored private var integrationNoticeTask: Task<Void, Never>?
    @ObservationIgnored private var isDeliveryReady = false
    @ObservationIgnored private var isSending = false

    init() {
        let helperPath = Bundle.main.bundleURL
            .appending(path: "Contents/Helpers/agent-light")
            .path
        integrations = IntegrationController(helperPath: helperPath)
        startKeyboardConnectionObserver()
        refreshConnection()
        refreshIntegrations()
        startAgentMonitor()
    }

    func refreshConnection() {
        hidAccessState = NuPhyHIDTransport.accessState
        if hidAccessState != .granted {
            isConnected = false
            isDeliveryReady = false
            keyboardModel = nil
            keyboardError = nil
        }

        Task {
            await keyboard.refresh()
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
            defer {
                isSending = false
                applyAgentStateIfChanged()
            }
            do {
                try await operation()
            } catch {
                if error is NuPhyHIDError {
                    deliveryState.markFailed()
                }
                keyboardError = error.localizedDescription
                hidLogger.error("Keyboard state send failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func startAgentMonitor() {
        do {
            agentStateObservation = try AgentStateChangeNotification.observe { [weak self] in
                Task { @MainActor [weak self] in
                    self?.applyAgentStateIfChanged()
                }
            }
        } catch {
            agentStateLogger.error(
                "Could not register Agent state notifications: \(String(describing: error), privacy: .public)"
            )
            startAgentFallbackMonitor()
        }
        applyAgentStateIfChanged()
    }

    private func startAgentFallbackMonitor() {
        agentFallbackTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
                self?.applyAgentStateIfChanged()
            }
        }
    }

    private func startKeyboardConnectionObserver() {
        keyboardConnectionTask = Task { [weak self] in
            guard let states = await self?.keyboard.connectionStates() else { return }
            for await state in states {
                guard !Task.isCancelled else { return }
                self?.handleKeyboardConnection(state)
            }
        }
    }

    private func handleKeyboardConnection(_ state: NuPhyHIDConnectionState) {
        hidAccessState = NuPhyHIDTransport.accessState
        switch state {
        case .disconnected:
            isConnected = false
            isDeliveryReady = false
            keyboardModel = nil
            keyboardError = NuPhyHIDError.deviceNotConnected.localizedDescription

        case .connected(let productName, .recovering(let error)):
            keyboardModel = productName
            isConnected = true
            isDeliveryReady = false
            keyboardError = error.localizedDescription

        case .connected(let productName, .rebuilding):
            keyboardModel = productName
            isConnected = true
            isDeliveryReady = false
            keyboardError = nil

        case .connected(let productName, .ready):
            let shouldReplayState = !isDeliveryReady
            keyboardModel = productName
            isConnected = true
            isDeliveryReady = true
            keyboardError = nil
            if shouldReplayState {
                deliveryState.connectionRestored()
                hidLogger.info("NuPhy Bluetooth keyboard HID session is ready")
                applyAgentStateIfChanged()
            }

        case .unavailable(let error):
            isConnected = false
            isDeliveryReady = false
            keyboardModel = nil
            keyboardError = error == .permissionDenied ? nil : error.localizedDescription
        }
    }

    private func applyAgentStateIfChanged() {
        guard var state = try? AgentStateFile().load() else { return }
        let now = Int64(Date().timeIntervalSince1970)
        let presentation = state.presentation(now: now)
        scheduleAgentExpiration(presentation.nextExpiration, now: now)

        guard hidAccessState == .granted, isConnected, isDeliveryReady, !isSending,
              deliveryState.shouldSend(presentation.command) else { return }

        perform {
            try await self.keyboard.send(presentation.command)
            self.deliveryState.markDelivered(presentation.command)
        }
    }

    private func scheduleAgentExpiration(_ expiration: Int64?, now: Int64) {
        agentExpirationTask?.cancel()
        guard let expiration else {
            agentExpirationTask = nil
            return
        }

        let delay = max(0, expiration - now)
        agentExpirationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self else { return }
            agentExpirationTask = nil
            applyAgentStateIfChanged()
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
    private var canAttemptDelivery = true

    func shouldSend(_ command: AgentLightCommand) -> Bool {
        canAttemptDelivery && command != lastDeliveredCommand
    }

    mutating func markDelivered(_ command: AgentLightCommand) {
        lastDeliveredCommand = command
        canAttemptDelivery = true
    }

    mutating func markFailed() {
        lastDeliveredCommand = nil
        canAttemptDelivery = false
    }

    mutating func connectionRestored() {
        lastDeliveredCommand = nil
        canAttemptDelivery = true
    }
}
