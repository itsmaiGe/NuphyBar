import AgentLightCore
import Foundation
import IOKit.hid
import Testing
@testable import AgentLightHID

private final class FakeDevice: HIDDeviceHandle, @unchecked Sendable {
    let identifier: UInt64
    let properties: HIDDeviceProperties
    var reports: [[UInt8]] = []
    var reportIDs: [CFIndex] = []
    var error: NuPhyHIDError?

    init(_ id: UInt64 = 1, profile: NuPhyHIDDeviceProfile = .halo75V2Bluetooth) {
        identifier = id
        switch profile {
        case .halo75V2Bluetooth:
            properties = HIDDeviceProperties(productName: "NuPhy Halo75 V2-1",
                transport: "Bluetooth Low Energy", maxOutputReportSize: 8,
                usagePage: 1, usage: 6, vendorID: 0x19F5, productID: 0x3246)
        case .halo75V2USB:
            properties = HIDDeviceProperties(productName: "NuPhy Halo75 V2 NuphyBar",
                transport: "USB", maxOutputReportSize: 32,
                usagePage: 0xFF60, usage: 0x61, vendorID: 0x19F5, productID: 0x32F5)
        case .air60V2Bluetooth:
            properties = HIDDeviceProperties(productName: "NuPhy Air60 V2-1",
                transport: "Bluetooth Low Energy", maxOutputReportSize: 8,
                usagePage: 1, usage: 6, vendorID: 0x19F5, productID: 0x1234)
        case .aulaF99ProBluetooth:
            properties = HIDDeviceProperties(productName: "AULA-F99Pro 5.0",
                transport: "Bluetooth Low Energy", maxOutputReportSize: 20,
                usagePage: 1, usage: 6, vendorID: 0x3554, productID: 0xFA07)
        }
    }

    func send(_ report: [UInt8], reportID: CFIndex) throws {
        if let error { throw error }
        reports.append(report)
        reportIDs.append(reportID)
    }
}

private final class FakeManager: HIDManagerSession, @unchecked Sendable {
    let queue: DispatchQueue
    let callbacks: HIDSessionCallbacks
    var devices: [any HIDDeviceHandle]
    var cancellationCount = 0
    var automaticallyCancel = true

    init(queue: DispatchQueue, callbacks: HIDSessionCallbacks, device: FakeDevice) {
        self.queue = queue
        self.callbacks = callbacks
        devices = [device]
    }

    func activate() {}
    func cancel() {
        cancellationCount += 1
        if automaticallyCancel { queue.async { self.callbacks.cancelled() } }
    }

    func remove(_ device: FakeDevice) {
        queue.sync {
            devices.removeAll { $0.identifier == device.identifier }
            callbacks.removed(device)
        }
    }

    func match(_ device: FakeDevice) {
        queue.sync {
            devices.removeAll { $0.identifier == device.identifier }
            devices.append(device)
            callbacks.matched(device)
        }
    }
}

private final class HIDRig: @unchecked Sendable {
    let device: FakeDevice
    private let lock = NSLock()
    private var sessions: [FakeManager] = []
    private var watchdogs: [(DispatchQueue, DispatchWorkItem)] = []

    init(device: FakeDevice = FakeDevice()) { self.device = device }

    var managers: [FakeManager] { lock.withLock { sessions } }

    func makeTransport() -> NuPhyHIDTransport {
        NuPhyHIDTransport(checkAccess: { .granted }, makeManager: { queue, callbacks in
            let manager = FakeManager(queue: queue, callbacks: callbacks, device: self.device)
            self.lock.withLock { self.sessions.append(manager) }
            return manager
        }, schedule: { queue, delay, work in
            if delay == 10 {
                self.lock.withLock { self.watchdogs.append((queue, work)) }
            } else {
                queue.async(execute: work)
            }
        })
    }

    func drain(_ transport: NuPhyHIDTransport) {
        for _ in 0..<8 { _ = transport.connectionState }
    }

    func fireWatchdogs() {
        let pending = lock.withLock {
            let pending = watchdogs
            watchdogs = []
            return pending
        }
        for (queue, item) in pending { queue.async(execute: item) }
    }
}

@Test("only AULA preserves its connection on a system permission refusal", arguments: [NuPhyHIDDeviceProfile.aulaF99ProBluetooth, .halo75V2Bluetooth, .halo75V2USB, .air60V2Bluetooth])
func profilePermissionRefusal(profile: NuPhyHIDDeviceProfile) throws {
    let rig = HIDRig(device: FakeDevice(profile: profile))
    let transport = rig.makeTransport()
    let original = transport.connectionState
    rig.device.error = .reportFailed(kIOReturnNotPermitted)
    #expect(throws: NuPhyHIDError.reportFailed(kIOReturnNotPermitted)) { try transport.send(.working) }
    rig.drain(transport)
    if profile == .aulaF99ProBluetooth {
        #expect(transport.connectionState == original)
        #expect(rig.managers.count == 1)
        #expect(rig.managers[0].cancellationCount == 0)
        rig.device.error = nil
        try transport.send(.working)
        #expect(rig.device.reports == [AULAF99ProRealtimeProtocol.encode(.working)])
    } else {
        #expect(rig.managers[0].cancellationCount == 1)
        #expect(rig.managers.count > 1)
    }
}

@Test("rebuilding rediscovers the same keyboard and sends through the new manager")
func rebuildSameDeviceThenSend() throws {
    let rig = HIDRig()
    let transport = rig.makeTransport()
    try transport.send(.working)
    transport.rebuildSession()
    rig.drain(transport)
    #expect(rig.managers.count == 2)
    guard case .connected(_, .ready) = transport.connectionState else {
        Issue.record("the rebuilt connection never became ready")
        return
    }
    try transport.send(.waiting)
    #expect(rig.device.reports.count == 2)
}

@Test("keyboard-only disconnect restores delivery without a Mac wake event")
func keyboardOnlyReconnect() throws {
    let rig = HIDRig()
    let transport = rig.makeTransport()
    let manager = rig.managers[0]
    manager.remove(rig.device)
    #expect(transport.connectionState == .disconnected)
    manager.match(rig.device)
    try transport.send(.idle)
    #expect(rig.device.reports.count == 1)
}

@Test("old manager callbacks cannot replace or remove the current device")
func obsoleteManagerCallbacks() throws {
    let rig = HIDRig()
    let transport = rig.makeTransport()
    let old = rig.managers[0]
    transport.rebuildSession()
    rig.drain(transport)
    old.remove(rig.device)
    old.match(FakeDevice(2))
    try transport.send(.working)
    #expect(rig.device.reports.count == 1)
}

@Test("failed reports recover without another agent event")
func failedReportRecovers() throws {
    let rig = HIDRig()
    let transport = rig.makeTransport()
    rig.device.error = .reportFailed(kIOReturnNotOpen)
    #expect(throws: NuPhyHIDError.self) { try transport.send(.working) }
    rig.drain(transport)
    rig.device.error = nil
    try transport.send(.working)
    #expect(rig.managers.count == 2)
    #expect(rig.device.reports.count == 1)
}

@Test("a stale delivery token never sends to a replacement connection")
func rejectOldConnectionDelivery() throws {
    let rig = HIDRig()
    let transport = rig.makeTransport()
    let old = try transport.send(.working)
    transport.rebuildSession()
    rig.drain(transport)
    #expect(throws: NuPhyHIDError.connectionChanged) {
        try transport.send(.waiting, expectedConnection: old)
    }
    #expect(rig.device.reports.count == 1)
    try transport.send(.idle)
}

@Test("repeated wake requests coalesce while manager cancellation is pending")
func repeatedWakeCoalesces() throws {
    let rig = HIDRig()
    let transport = rig.makeTransport()
    let old = rig.managers[0]
    old.queue.sync { old.automaticallyCancel = false }
    for _ in 0..<20 { transport.rebuildSession() }
    rig.drain(transport)
    #expect(rig.managers.count == 1)
    #expect(old.cancellationCount == 1)
    old.queue.sync { old.callbacks.cancelled() }
    rig.drain(transport)
    #expect(rig.managers.count == 2)
    try transport.send(.working)
}

@Test("stalled cancellation is visible and does not create parallel managers")
func cancellationTimeoutIsVisible() throws {
    let rig = HIDRig()
    let transport = rig.makeTransport()
    let old = rig.managers[0]
    old.queue.sync { old.automaticallyCancel = false }
    transport.rebuildSession()
    rig.drain(transport)
    rig.fireWatchdogs()
    rig.drain(transport)
    #expect(transport.connectionState == .unavailable(.cancellationTimedOut))
    #expect(rig.managers.count == 1)
    old.queue.sync { old.callbacks.cancelled() }
    rig.drain(transport)
    try transport.send(.working)
    #expect(rig.managers.count == 2)
}

@Test("all supported profiles keep their protocol after a manager rebuild", arguments: [
    NuPhyHIDDeviceProfile.halo75V2USB, .halo75V2Bluetooth, .air60V2Bluetooth, .aulaF99ProBluetooth,
])
func profilesSurviveRebuild(profile: NuPhyHIDDeviceProfile) throws {
    let rig = HIDRig(device: FakeDevice(profile: profile))
    let transport = rig.makeTransport()
    try transport.send(.working)
    transport.rebuildSession()
    rig.drain(transport)
    try transport.send(.idle)
    #expect(rig.device.reports.count == 2)
    let expectedID: CFIndex = switch profile {
    case .halo75V2USB: 0
    case .halo75V2Bluetooth, .air60V2Bluetooth: 1
    case .aulaF99ProBluetooth: CFIndex(AULAF99ProRealtimeProtocol.reportID)
    }
    #expect(rig.device.reportIDs == [expectedID, expectedID])
}

@Test("unplugging a preferred USB device selects the remaining Bluetooth device")
func preferredDeviceRemovalFallsBack() throws {
    let rig = HIDRig()
    let transport = rig.makeTransport()
    let manager = rig.managers[0]
    let usb = FakeDevice(2, profile: .halo75V2USB)
    manager.match(usb)
    try transport.send(.working)
    #expect(usb.reports.count == 1)
    manager.remove(usb)
    try transport.send(.waiting)
    #expect(rig.device.reports.count == 1)
}

@Test("refresh replaces an absent device even when its removal callback was missed")
func missedRemovalCallback() throws {
    let rig = HIDRig()
    let transport = rig.makeTransport()
    let manager = rig.managers[0]
    let replacement = FakeDevice(2)
    manager.queue.sync { manager.devices = [replacement] }
    transport.refresh()
    rig.drain(transport)
    try transport.send(.working)
    #expect(replacement.reports.count == 1)
    #expect(rig.device.reports.isEmpty)
}

@Test("a replacement match recovers automatically when removal was missed")
func replacementMatchAfterMissedRemoval() throws {
    let rig = HIDRig()
    let transport = rig.makeTransport()
    let manager = rig.managers[0]
    let replacement = FakeDevice(2)
    manager.queue.sync {
        manager.devices = [replacement]
        manager.callbacks.matched(replacement)
    }
    try transport.send(.working)
    #expect(replacement.reports.count == 1)
    #expect(rig.device.reports.isEmpty)
}

@Test("starting with no keyboard automatically recovers when a keyboard appears")
func bootWithoutKeyboard() throws {
    let rig = HIDRig()
    let transport = NuPhyHIDTransport(checkAccess: { .granted }, makeManager: { queue, callbacks in
        let manager = FakeManager(queue: queue, callbacks: callbacks, device: rig.device)
        manager.devices = []
        queue.async {
            manager.devices = [rig.device]
            manager.callbacks.matched(rig.device)
        }
        return manager
    })
    rig.drain(transport)
    try transport.send(.idle)
    #expect(rig.device.reports.count == 1)
}

@Test("twenty rebuild cycles preserve delivery without a task timeout")
func repeatedRebuilds() throws {
    let rig = HIDRig()
    let transport = rig.makeTransport()
    for _ in 0..<20 {
        transport.rebuildSession()
        rig.drain(transport)
        try transport.send(.working)
    }
    #expect(rig.device.reports.count == 20)
    #expect(rig.managers.count == 21)
}
