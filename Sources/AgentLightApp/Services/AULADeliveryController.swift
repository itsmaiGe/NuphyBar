import AgentLightCore
import AgentLightHID
@preconcurrency import AppKit
import Carbon
import IOKit.hid
import Observation

enum AULAPauseReason: String {
    case sleeping, secureInput, accessDenied

    var message: String {
        switch self {
        case .sleeping: "AULA 灯光已暂停，屏幕唤醒后自动恢复"
        case .secureInput: "系统安全输入已开启，AULA 灯光将在解除后自动恢复"
        case .accessDenied: "系统暂不允许 AULA 灯光写入，30 秒后重试"
        }
    }
}

@MainActor
final class AULAPowerMonitor {
    private let center: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var sleeping = false
    private var screenSleeping: Bool

    init(center: NotificationCenter = NSWorkspace.shared.notificationCenter,
         screenSleeping: Bool = CGDisplayIsAsleep(CGMainDisplayID()) != 0,
         changed: @escaping @MainActor () -> Void) {
        self.center = center
        self.screenSleeping = screenSleeping
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    switch name {
                    case NSWorkspace.willSleepNotification: self.sleeping = true
                    case NSWorkspace.didWakeNotification: self.sleeping = false
                    case NSWorkspace.screensDidSleepNotification: self.screenSleeping = true
                    case NSWorkspace.screensDidWakeNotification: self.screenSleeping = false
                    default: break
                    }
                    changed()
                }
            })
        }
    }

    func pauseReason(secureInput: Bool = IsSecureEventInputEnabled()) -> AULAPauseReason? {
        if sleeping || screenSleeping { return .sleeping }
        return secureInput ? .secureInput : nil
    }

    deinit { for observer in observers { center.removeObserver(observer) } }
}

@MainActor
@Observable
final class AULADeliveryController {
    private(set) var notice: String?
    private let keyboard: any KeyboardControlling
    private let environment: @MainActor () -> AULAPauseReason?
    private let clock: @MainActor () -> TimeInterval
    private let diagnostics: RecoveryDiagnostics
    private var connection: HIDConnectionIdentity?
    private var command: AgentLightCommand = .idle
    private var accepted: AgentLightCommand?
    private var generation: UInt64 = 0
    private(set) var inFlight = false
    private var retryAt: TimeInterval = 0
    private var lastPause: AULAPauseReason?

    init(keyboard: any KeyboardControlling,
         environment: @escaping @MainActor () -> AULAPauseReason?,
         clock: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         diagnostics: RecoveryDiagnostics = .shared) {
        self.keyboard = keyboard
        self.environment = environment
        self.clock = clock
        self.diagnostics = diagnostics
    }

    func connect(_ identity: HIDConnectionIdentity?) {
        guard connection != identity else { return }
        connection = identity
        generation &+= 1
        accepted = nil
        retryAt = 0
        notice = nil
    }

    func update(_ target: AgentLightCommand, refresh: Bool = false) {
        if command != target { command = target; generation &+= 1 }
        let pause = environment()
        if pause != lastPause {
            generation &+= 1
            accepted = nil
            retryAt = 0
            lastPause = pause
            diagnostics.record("aula.pause.changed", fields: ["reason": pause?.rawValue ?? "resumed"])
        }
        if let pause { notice = pause.message; return }
        guard clock() >= retryAt else { return }
        guard let connection, !inFlight else { return }
        guard accepted != target || (refresh && target != .idle) else { notice = nil; return }
        let attemptGeneration = generation
        inFlight = true
        Task {
            // Recheck after scheduling, before admitting a hardware write.
            guard self.connection == connection, generation == attemptGeneration, environment() == nil else {
                inFlight = false
                update(command)
                return
            }
            do {
                try await keyboard.send(target, connection: connection)
                inFlight = false
                if self.connection == connection, generation == attemptGeneration, environment() == nil {
                    if accepted != target {
                        diagnostics.record("aula.delivery.accepted", fields: [
                            "command": String(describing: target), "connection": connection.selectionID.uuidString,
                        ])
                    }
                    accepted = target
                    notice = nil
                }
                update(command)
            } catch {
                inFlight = false
                guard self.connection == connection, generation == attemptGeneration else {
                    update(command)
                    return
                }
                accepted = nil
                retryAt = clock() + 30
                if let pause = environment() {
                    notice = pause.message
                } else if error as? NuPhyHIDError == .reportFailed(kIOReturnNotPermitted) {
                    notice = AULAPauseReason.accessDenied.message
                } else {
                    notice = error.localizedDescription
                }
                diagnostics.record("aula.delivery.failed", fields: ["error": error.localizedDescription])
            }
        }
    }
}
