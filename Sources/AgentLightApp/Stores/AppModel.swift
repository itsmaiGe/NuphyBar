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
    var agentStateError: String?
    var isDeliveryReady = false
    var integrationError: String?
    var diagnosticsError: String?
    var integrationStatuses: [AgentProvider: IntegrationStatus] = [:]
    var hidAccessState: NuPhyHIDAccessState = .unknown
    var integrationNoticeProvider: AgentProvider?

    private let keyboard: any KeyboardControlling
    private let stateFile: AgentStateFile
    private let checkAccess: @Sendable () -> NuPhyHIDAccessState
    private let now: @Sendable () -> Int64
    private let uptime: @Sendable () -> TimeInterval
    private let diagnostics: RecoveryDiagnostics
    private let integrations: IntegrationController
    @ObservationIgnored private(set) var deliveryState = AgentCommandDeliveryState()
    @ObservationIgnored private var agentStateObservation: AgentStateChangeObservation?
    @ObservationIgnored private var lastAgentState: AgentState?
    @ObservationIgnored private var stateRevision: UInt64 = 0
    @ObservationIgnored private var agentExpirationTask: Task<Void, Never>?
    @ObservationIgnored private var agentFallbackTask: Task<Void, Never>?
    @ObservationIgnored private var aulaRealtimeRGBKeepaliveTask: Task<Void, Never>?
    @ObservationIgnored private var keyboardConnectionTask: Task<Void, Never>?
    @ObservationIgnored private var integrationNoticeTask: Task<Void, Never>?
    @ObservationIgnored private var systemLifecycleMonitor: SystemLifecycleMonitor?
    @ObservationIgnored private var aulaPowerMonitor: AULAPowerMonitor?
    private var aulaDelivery: AULADeliveryController?
    var aulaNotice: String? { isAULA ? aulaDelivery?.notice : nil }
    private var isAULA: Bool {
        keyboardModel?.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("AULA-F99Pro 5.0") == .orderedSame
    }

    init(keyboard: any KeyboardControlling = KeyboardController(),
         stateFile: AgentStateFile = AgentStateFile(),
         checkAccess: @escaping @Sendable () -> NuPhyHIDAccessState = { NuPhyHIDTransport.accessState },
         now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970) },
         uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         diagnostics: RecoveryDiagnostics = .shared,
         startMonitoring: Bool = true) {
        self.keyboard = keyboard
        self.stateFile = stateFile
        self.checkAccess = checkAccess
        self.now = now
        self.uptime = uptime
        self.diagnostics = diagnostics
        let helperPath = Bundle.main.bundleURL
            .appending(path: "Contents/Helpers/agent-light")
            .path
        integrations = IntegrationController(helperPath: helperPath)
        aulaDelivery = AULADeliveryController(keyboard: keyboard, environment: { [weak self] in
            self?.aulaPowerMonitor?.pauseReason()
        }, diagnostics: diagnostics)
        diagnostics.record("app.started", fields: [
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development",
            "source": Bundle.main.object(forInfoDictionaryKey: "NuphyBarSourceRevision") as? String ?? "development",
        ])
        if startMonitoring {
            aulaPowerMonitor = AULAPowerMonitor { [weak self] in
                guard let self, self.isAULA else { return }
                self.applyAgentStateIfChanged()
            }
            startKeyboardConnectionObserver()
            refreshConnection()
            refreshIntegrations()
            startAgentMonitor()
            startSystemLifecycleMonitor()
        }
    }

    deinit {
        agentExpirationTask?.cancel()
        agentFallbackTask?.cancel()
        aulaRealtimeRGBKeepaliveTask?.cancel()
        keyboardConnectionTask?.cancel()
        integrationNoticeTask?.cancel()
    }

    func refreshConnection() {
        hidAccessState = checkAccess()
        if hidAccessState != .granted {
            isConnected = false
            isDeliveryReady = false
            deliveryState.connect(nil)
            aulaDelivery?.connect(nil)
            keyboardModel = nil
            keyboardError = nil
            updateAULARealtimeRGBKeepalive()
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

    func exportRecoveryDiagnostics() {
        do {
            let data = try diagnostics.export()
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "NuphyBar-recovery-diagnostics.json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            diagnosticsError = nil
        } catch {
            diagnosticsError = "诊断导出失败：\(error.localizedDescription)"
        }
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

    private func startAgentMonitor() {
        do {
            agentStateObservation = try AgentStateChangeNotification.observe { [weak self] in
                Task { @MainActor [weak self] in
                    self?.handleAgentStateChange()
                }
            }
        } catch {
            agentStateLogger.error(
                "Could not register Agent state notifications: \(String(describing: error), privacy: .public)"
            )
        }
        startAgentFallbackMonitor()
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
                guard let self else { return }
                handleAgentStateChange()
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

    private func startSystemLifecycleMonitor() {
        systemLifecycleMonitor = SystemLifecycleMonitor(
            resumeHandler: { [weak self] in
                self?.rebuildHIDSessionAfterWake()
            }
        )
    }

    private func rebuildHIDSessionAfterWake() {
        if isAULA {
            applyAgentStateIfChanged()
            return
        }
        isDeliveryReady = false
        deliveryState.connect(nil)
        hidLogger.info("Mac woke from sleep; rebuilding the keyboard HID session")
        Task {
            await keyboard.rebuildSession()
        }
    }

    func handleKeyboardConnection(_ state: NuPhyHIDConnectionState) {
        hidAccessState = checkAccess()
        if case .connected(let name, .ready(let identity)) = state,
           name.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("AULA-F99Pro 5.0") == .orderedSame {
            aulaDelivery?.connect(identity)
        } else {
            aulaDelivery?.connect(nil)
        }
        if case .connected(_, .ready(let identity)) = state {
            deliveryState.connect(identity)
        } else {
            deliveryState.connect(nil)
        }
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
            keyboardModel = productName
            isConnected = true
            isDeliveryReady = true
            keyboardError = nil
            hidLogger.info("Keyboard HID session is ready")
            applyAgentStateIfChanged()

        case .unavailable(let error):
            isConnected = false
            isDeliveryReady = false
            keyboardModel = nil
            keyboardError = error == .permissionDenied ? nil : error.localizedDescription
        }
        updateAULARealtimeRGBKeepalive()
    }

    func applyAgentStateIfChanged(force: Bool = false) {
        var state: AgentState
        do {
            state = try stateFile.load()
            agentStateError = nil
        } catch {
            if agentStateError != error.localizedDescription {
                agentStateLogger.error("Cannot read Agent state: \(String(describing: error), privacy: .public)")
            }
            agentStateError = error.localizedDescription
            return
        }
        if state != lastAgentState {
            stateRevision &+= 1
            lastAgentState = state
            diagnostics.record("state.target.changed", fields: [
                "revision": String(stateRevision),
            ])
        }
        let now = now()
        let presentation = state.presentation(now: now)
        scheduleAgentExpiration(presentation.nextExpiration, now: now)

        if isAULA {
            guard hidAccessState == .granted else { return }
            aulaDelivery?.update(presentation.command, refresh: force)
            return
        }
        deliveryState.update(command: presentation.command, revision: stateRevision)
        // USB firmware expires active states after 15 minutes. Renew its state
        // every five minutes; Bluetooth remains change-driven.
        let isHaloUSB = keyboardModel?.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("NuPhy Halo75 V2 NuphyBar") == .orderedSame
        guard hidAccessState == .granted, isConnected, isDeliveryReady,
              let attempt = deliveryState.begin(force: force && presentation.command != .idle,
                refreshInterval: isHaloUSB ? 5 * 60 : nil, now: uptime()) else { return }
        diagnostics.record("delivery.requested", fields: ["revision": String(stateRevision),
            "command": String(describing: attempt.target.command),
            "connection": attempt.connection.selectionID.uuidString])
        Task {
            do {
                try await keyboard.send(attempt.target.command, connection: attempt.connection)
                if deliveryState.finish(attempt, succeeded: true, now: uptime()) {
                    keyboardError = nil
                }
            } catch {
                if deliveryState.finish(attempt, succeeded: false, now: uptime()) {
                    keyboardError = error.localizedDescription
                }
                hidLogger.error("Keyboard state send failed: \(String(describing: error), privacy: .public)")
            }
            applyAgentStateIfChanged()
        }
    }

    private func handleAgentStateChange() {
        applyAgentStateIfChanged()
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

    private func updateAULARealtimeRGBKeepalive() {
        aulaRealtimeRGBKeepaliveTask?.cancel()
        aulaRealtimeRGBKeepaliveTask = nil

        guard hidAccessState == .granted,
              isConnected,
              isDeliveryReady,
              keyboardModel?.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("AULA-F99Pro 5.0") == .orderedSame else { return }

        aulaRealtimeRGBKeepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                self?.refreshAULARealtimeRGB()
            }
        }
    }

    private func refreshAULARealtimeRGB() {
        guard hidAccessState == .granted,
              isConnected,
              isDeliveryReady,
              keyboardModel?.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("AULA-F99Pro 5.0") == .orderedSame else { return }
        applyAgentStateIfChanged(force: true)
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
