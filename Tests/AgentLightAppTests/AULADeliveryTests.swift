import AgentLightCore
import AgentLightHID
import AppKit
import IOKit.hid
import Testing
@testable import AgentLightApp

private actor AULAKeyboard: KeyboardControlling {
    var commands: [AgentLightCommand] = []
    var failure: NuPhyHIDError?
    var held: CheckedContinuation<Void, Never>?
    var holdNext = false
    func connectionStates() -> AsyncStream<NuPhyHIDConnectionState> { AsyncStream { $0.finish() } }
    func refresh() {}
    func rebuildSession() { Issue.record("AULA controller must not rebuild for a security pause") }
    func configure(failure: NuPhyHIDError? = nil, hold: Bool = false) { self.failure = failure; holdNext = hold }
    func release() { held?.resume(); held = nil }
    func send(_ command: AgentLightCommand, connection: HIDConnectionIdentity) async throws {
        commands.append(command)
        if holdNext { holdNext = false; await withCheckedContinuation { held = $0 } }
        if let failure { throw failure }
    }
}

@MainActor
private final class AULAEnvironment {
    var pause: AULAPauseReason?
    var time: TimeInterval = 0
}

@MainActor
private func settle(_ controller: AULADeliveryController) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while controller.inFlight, ContinuousClock.now < deadline { await Task.yield() }
    #expect(!controller.inFlight)
}

@MainActor
private func makeController(_ keyboard: AULAKeyboard, _ environment: AULAEnvironment) -> AULADeliveryController {
    let controller = AULADeliveryController(keyboard: keyboard, environment: { environment.pause },
        clock: { environment.time }, diagnostics: RecoveryDiagnostics())
    controller.connect(HIDConnectionIdentity(sessionID: UUID(), deviceID: 1))
    return controller
}

@MainActor
@Test("AULA security and sleep pauses send nothing and restore the latest idle", arguments: [AULAPauseReason.secureInput, .sleeping])
func aulaPauseRestoresLatest(reason: AULAPauseReason) async {
    let keyboard = AULAKeyboard(), environment = AULAEnvironment()
    let controller = makeController(keyboard, environment)
    controller.update(.working)
    await settle(controller)
    environment.pause = reason
    for _ in 0..<100 { controller.update(.working, refresh: true) }
    controller.update(.idle)
    await settle(controller)
    #expect(await keyboard.commands == [.working])
    #expect(controller.notice == reason.message)
    environment.pause = nil
    controller.update(.idle)
    await settle(controller)
    for _ in 0..<100 { controller.update(.idle, refresh: true) }
    await settle(controller)
    #expect(await keyboard.commands == [.working, .idle])
    #expect(controller.notice == nil)
}

@MainActor
@Test("AULA rejects queued writes when sleep begins before the task executes")
func aulaQueuedWriteSuspends() async {
    let keyboard = AULAKeyboard(), environment = AULAEnvironment()
    let controller = makeController(keyboard, environment)
    controller.update(.working)
    environment.pause = .sleeping
    await settle(controller)
    #expect(await keyboard.commands.isEmpty)
    environment.pause = nil
    controller.update(.waiting)
    await settle(controller)
    #expect(await keyboard.commands == [.waiting])
}

@MainActor
@Test("AULA permission refusal backs off without blocking recovery after security clears")
func aulaPermissionBackoff() async {
    let keyboard = AULAKeyboard(), environment = AULAEnvironment()
    await keyboard.configure(failure: .reportFailed(kIOReturnNotPermitted))
    let controller = makeController(keyboard, environment)
    controller.update(.working)
    await settle(controller)
    for tick in 1..<30 {
        environment.time = Double(tick)
        controller.update(.working, refresh: true)
    }
    await settle(controller)
    #expect(await keyboard.commands.count == 1)
    environment.pause = .secureInput
    controller.update(.working)
    await keyboard.configure()
    environment.pause = nil
    controller.update(.working)
    await settle(controller)
    #expect(await keyboard.commands.count == 2)
    #expect(controller.notice == nil)
}

@MainActor
@Test("AULA keeps one in-flight write and ignores an old connection completion")
func aulaOldCompletion() async {
    let keyboard = AULAKeyboard(), environment = AULAEnvironment()
    await keyboard.configure(hold: true)
    let controller = makeController(keyboard, environment)
    controller.update(.working)
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while await keyboard.held == nil, ContinuousClock.now < deadline { await Task.yield() }
    #expect(await keyboard.held != nil)
    controller.connect(nil)
    controller.connect(HIDConnectionIdentity(sessionID: UUID(), deviceID: 2))
    controller.update(.idle)
    for _ in 0..<100 { controller.update(.idle, refresh: true) }
    #expect(await keyboard.commands.count == 1)
    await keyboard.release()
    await settle(controller)
    #expect(await keyboard.commands == [.working, .idle])
}

@MainActor
@Test("AULA simulated eight-hour keepalive has no task expiry and stops on idle")
func aulaEightHourKeepalive() async {
    let keyboard = AULAKeyboard(), environment = AULAEnvironment()
    let controller = makeController(keyboard, environment)
    for second in 0..<28_800 {
        environment.time = Double(second)
        controller.update(.working, refresh: true)
        await settle(controller)
    }
    #expect(await keyboard.commands.count == 28_800)
    controller.update(.idle)
    await settle(controller)
    for _ in 0..<60 { controller.update(.idle, refresh: true) }
    await settle(controller)
    #expect(await keyboard.commands.count == 28_801)
    #expect(await keyboard.commands.last == .idle)
}

@MainActor
@Test("AULA screen sleep stays paused through a background system wake")
func aulaPowerEvents() {
    let center = NotificationCenter()
    let monitor = AULAPowerMonitor(center: center, screenSleeping: false, changed: {})
    #expect(monitor.pauseReason(secureInput: false) == nil)
    center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
    center.post(name: NSWorkspace.willSleepNotification, object: nil)
    center.post(name: NSWorkspace.didWakeNotification, object: nil)
    #expect(monitor.pauseReason(secureInput: false) == .sleeping)
    center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
    #expect(monitor.pauseReason(secureInput: false) == nil)
    #expect(monitor.pauseReason(secureInput: true) == .secureInput)
    withExtendedLifetime(monitor) {}
}
