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

private final class TestUptime: @unchecked Sendable {
    private let lock = NSLock()
    private var time: TimeInterval = 0
    func read() -> TimeInterval { lock.withLock { time } }
    func advance(to value: TimeInterval) { lock.withLock { time = value } }
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
