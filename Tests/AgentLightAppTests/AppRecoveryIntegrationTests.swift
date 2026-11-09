import AgentLightCore
import AgentLightHID
import Foundation
import Testing
@testable import AgentLightApp

private actor RecordingKeyboard: KeyboardControlling {
    private(set) var commands: [AgentLightCommand] = []
    func connectionStates() -> AsyncStream<NuPhyHIDConnectionState> { AsyncStream { $0.finish() } }
    func refresh() {}
    func rebuildSession() {}
    func send(_ command: AgentLightCommand, connection: HIDConnectionIdentity) throws { commands.append(command) }
}

private actor DelayedConfirmationKeyboard: KeyboardControlling {
    private(set) var commands: [AgentLightCommand] = []
    private var confirmation: CheckedContinuation<Void, Never>?
    func connectionStates() -> AsyncStream<NuPhyHIDConnectionState> { AsyncStream { $0.finish() } }
    func refresh() {}
    func rebuildSession() {}
    func send(_ command: AgentLightCommand, connection: HIDConnectionIdentity) async {
        commands.append(command)
        if command == .complete {
            await withCheckedContinuation { confirmation = $0 }
        }
    }
    func release() { confirmation?.resume(); confirmation = nil }
}

@MainActor
@Test("completion expiry during delayed confirmation restores idle on every supported profile", arguments: [
    "NuPhy Halo75 V2 NuphyBar", "NuPhy Halo75 V2-1", "NuPhy Air60 V2-1", "AULA-F99Pro 5.0",
])
func delayedGreenConfirmationRestoresIdle(productName: String) async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = AgentStateFile(url: folder.appending(path: "state.json"))
    let clock = TestUptime()
    let keyboard = DelayedConfirmationKeyboard()
    defer { Task { await keyboard.release() } }
    let app = AppModel(keyboard: keyboard, stateFile: file, checkAccess: { .granted },
        now: { Int64(clock.read()) }, uptime: { clock.read() },
        diagnostics: RecoveryDiagnostics(), startMonitoring: false)
    app.handleKeyboardConnection(.connected(productName: productName,
        delivery: .ready(HIDConnectionIdentity(sessionID: UUID(), deviceID: 1))))
    let initialDeadline = ContinuousClock.now.advanced(by: .seconds(2))
    while ContinuousClock.now < initialDeadline {
        if await keyboard.commands.count == 1 && app.deliveryState.inFlight == nil { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(await keyboard.commands == [.idle])
    _ = try file.apply(.init(provider: .codex, sessionID: "completion-race", status: .complete), now: 0)
    app.applyAgentStateIfChanged()
    let greenDeadline = ContinuousClock.now.advanced(by: .seconds(2))
    while await keyboard.commands.count < 2, ContinuousClock.now < greenDeadline {
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(await keyboard.commands == [.idle, .complete])
    clock.advance(to: 20)
    app.applyAgentStateIfChanged()
    await keyboard.release()
    let idleDeadline = ContinuousClock.now.advanced(by: .seconds(2))
    while await keyboard.commands.count < 3, ContinuousClock.now < idleDeadline {
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(await keyboard.commands == [.idle, .complete, .idle])
    withExtendedLifetime(app) { }
}

private final class TestUptime: @unchecked Sendable {
    private let lock = NSLock()
    private var time: TimeInterval = 0
    func read() -> TimeInterval { lock.withLock { time } }
    func advance(to value: TimeInterval) { lock.withLock { time = value } }
}

private final class TestTurnEvidence: @unchecked Sendable {
    private let lock = NSLock()
    private var ended = false
    func finish() { lock.withLock { ended = true } }
    func read() -> CodexTurnEvidence? {
        lock.withLock { ended ? CodexTurnEvidence(closedTurns: ["turn"], endedAt: 200) : nil }
    }
}

@MainActor
@Test("five-second fallback clears a missed end without another hook or process exit", arguments: [
    "NuPhy Halo75 V2-1", "AULA-F99Pro 5.0",
], [AgentProvider.codex, .claudeCode])
func automaticMissedEndReconciliation(productName: String, provider: AgentProvider) async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let evidence = TestTurnEvidence()
    let file = AgentStateFile(url: folder.appending(path: "state.json"), ownerStatus: { _ in .alive },
        turnEvidence: { _, _, _ in evidence.read() },
        claudeEvidence: { _, _, _ in evidence.read().map { ClaudeTurnEvidence(endedAt: $0.endedAt, status: .error) } })
    _ = try file.apply(.init(provider: provider, sessionID: "missed-end", status: .working,
        turnID: "turn", lifecycle: .begin, occurredAt: 1), now: 1)
    let keyboard = RecordingKeyboard()
    let app = AppModel(keyboard: keyboard, stateFile: file, checkAccess: { .granted },
        now: { 100 }, diagnostics: RecoveryDiagnostics(), startMonitoring: true)
    app.handleKeyboardConnection(.connected(productName: productName,
        delivery: .ready(HIDConnectionIdentity(sessionID: UUID(), deviceID: 1))))
    await waitForCommands(1, keyboard: keyboard)
    evidence.finish()
    let deadline = ContinuousClock.now.advanced(by: .seconds(7))
    while ContinuousClock.now < deadline {
        if await keyboard.commands.last == .idle { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(await keyboard.commands.first == .working)
    #expect(await keyboard.commands.last == .idle)
    #expect(try file.load().sessions.isEmpty)
    withExtendedLifetime(app) { }
}

@MainActor
@Test("five-second reconciliation renews Halo USB while Bluetooth stays quiet", arguments: [
    "NuPhy Halo75 V2 NuphyBar", "NuPhy Halo75 V2-1", "NuPhy Air60 V2-1",
])
func appRenewsOnlyHaloUSB(productName: String) async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = AgentStateFile(url: folder.appending(path: "state.json"))
    _ = try file.apply(.init(provider: .codex, sessionID: "long-task", status: .working), now: 1)
    let keyboard = RecordingKeyboard()
    let clock = TestUptime()
    let app = AppModel(keyboard: keyboard, stateFile: file, checkAccess: { .granted },
        now: { 100 }, uptime: { clock.read() }, diagnostics: RecoveryDiagnostics(), startMonitoring: false)
    app.handleKeyboardConnection(.connected(productName: productName,
        delivery: .ready(HIDConnectionIdentity(sessionID: UUID(), deviceID: 1))))
    await waitForCommands(1, keyboard: keyboard)
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while app.deliveryState.inFlight != nil, ContinuousClock.now < deadline { await Task.yield() }
    #expect(app.deliveryState.inFlight == nil)
    clock.advance(to: 301)
    app.applyAgentStateIfChanged()
    if productName == "NuPhy Halo75 V2 NuphyBar" {
        await waitForCommands(2, keyboard: keyboard)
        #expect(await keyboard.commands == [.working, .working])
    } else {
        #expect(app.deliveryState.inFlight == nil)
        #expect(await keyboard.commands == [.working])
    }
}

@MainActor
private func waitForCommands(_ count: Int, keyboard: RecordingKeyboard) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while ContinuousClock.now < deadline {
        if await keyboard.commands.count >= count { return }
        await Task.yield()
    }
    Issue.record("the app did not send its target after reconnecting")
}

@MainActor
@Test("Interrupt restores idle and cannot be renewed by a later USB reconciliation", arguments: [
    "NuPhy Halo75 V2 NuphyBar", "NuPhy Halo75 V2-1", "NuPhy Air60 V2-1",
])
func interruptedTurnStopsRenewal(productName: String) async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = AgentStateFile(url: folder.appending(path: "state.json"))
    _ = try file.apply(.init(provider: .codex, sessionID: "interrupted", status: .working,
        turnID: "turn", lifecycle: .begin, occurredAt: 1), now: 1)
    let keyboard = RecordingKeyboard()
    let clock = TestUptime()
    let app = AppModel(keyboard: keyboard, stateFile: file, checkAccess: { .granted },
        now: { 100 }, uptime: { clock.read() }, diagnostics: RecoveryDiagnostics(), startMonitoring: false)
    app.handleKeyboardConnection(.connected(productName: productName,
        delivery: .ready(HIDConnectionIdentity(sessionID: UUID(), deviceID: 1))))
    await waitForCommands(1, keyboard: keyboard)
    _ = try file.apply(.init(provider: .codex, sessionID: "interrupted", status: .idle,
        turnID: "turn", lifecycle: .endTurn, occurredAt: 2), now: 2)
    app.applyAgentStateIfChanged()
    await waitForCommands(2, keyboard: keyboard)
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while app.deliveryState.inFlight != nil, ContinuousClock.now < deadline { await Task.yield() }
    clock.advance(to: 301)
    _ = try file.apply(.init(provider: .codex, sessionID: "interrupted", status: .working,
        turnID: "turn", lifecycle: .activity, occurredAt: 3), now: 3)
    app.applyAgentStateIfChanged()
    #expect(try file.load().sessions.isEmpty)
    #expect(app.deliveryState.inFlight == nil)
    #expect(await keyboard.commands == [.working, .idle])
}

@MainActor
@Test("the app reads offline completion and delivers idle on reconnect", arguments: ["NuPhy Halo75 V2-1", "AULA-F99Pro 5.0"])
func appRestoresLatestPersistedState(productName: String) async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = AgentStateFile(url: folder.appending(path: "state.json"))
    _ = try file.apply(.init(provider: .codex, sessionID: "test", status: .working), now: 1)
    let keyboard = RecordingKeyboard()
    let app = AppModel(keyboard: keyboard, stateFile: file, checkAccess: { .granted },
        now: { 100 }, diagnostics: RecoveryDiagnostics(), startMonitoring: false)
    app.handleKeyboardConnection(.connected(productName: productName,
        delivery: .ready(HIDConnectionIdentity(sessionID: UUID(), deviceID: 1))))
    await waitForCommands(1, keyboard: keyboard)
    app.handleKeyboardConnection(.disconnected)
    _ = try file.apply(.init(provider: .codex, sessionID: "test", status: .complete), now: 50)
    app.handleKeyboardConnection(.connected(productName: productName,
        delivery: .ready(HIDConnectionIdentity(sessionID: UUID(), deviceID: 1))))
    await waitForCommands(2, keyboard: keyboard)
    #expect(await keyboard.commands == [.working, .idle])
}

@MainActor
@Test("polling reads changed contents even when the file timestamp is unchanged", arguments: ["NuPhy Halo75 V2-1", "AULA-F99Pro 5.0"])
func appReadsChangedContents(productName: String) async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = AgentStateFile(url: folder.appending(path: "state.json"))
    _ = try file.apply(.init(provider: .codex, sessionID: "test", status: .working), now: 1)
    let originalDate = try file.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    let keyboard = RecordingKeyboard()
    let app = AppModel(keyboard: keyboard, stateFile: file, checkAccess: { .granted },
        now: { 100 }, diagnostics: RecoveryDiagnostics(), startMonitoring: false)
    app.handleKeyboardConnection(.connected(productName: productName,
        delivery: .ready(HIDConnectionIdentity(sessionID: UUID(), deviceID: 1))))
    await waitForCommands(1, keyboard: keyboard)
    _ = try file.apply(.init(provider: .codex, sessionID: "test", status: .waiting), now: 1)
    if let originalDate {
        try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: file.url.path)
    }
    app.applyAgentStateIfChanged()
    await waitForCommands(2, keyboard: keyboard)
    #expect(await keyboard.commands == [.working, .waiting])
}
