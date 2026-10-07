import AgentLightCore
import CoreGraphics
import Foundation
import IOKit.hid
import IOKit.hidsystem

public enum NuPhyHIDAccessState: Equatable, Sendable {
    case granted
    case denied
    case unknown
}

public enum NuPhyHIDError: LocalizedError, CustomStringConvertible, Equatable, Sendable {
    case permissionDenied
    case managerOpenFailed(IOReturn)
    case deviceNotConnected
    case reportFailed(IOReturn)
    case connectionChanged
    case cancellationTimedOut

    public var description: String {
        switch self {
        case .permissionDenied: return "keyboard HID access has not been granted"
        case .managerOpenFailed(let status): return "could not open the HID manager (\(hex(status)))"
        case .deviceNotConnected: return "no compatible keyboard is connected"
        case .reportFailed(let status): return "sending a keyboard report failed (\(hex(status)))"
        case .connectionChanged: return "the keyboard connection changed before delivery"
        case .cancellationTimedOut: return "the HID manager did not finish cancelling"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: return "需要允许 NuphyBar 访问键盘 HID 接口"
        case .managerOpenFailed: return "无法访问 macOS HID 设备管理器"
        case .deviceNotConnected: return "未找到已连接的 NuphyBar 兼容键盘"
        case .reportFailed: return "无法向键盘发送灯光状态"
        case .connectionChanged: return "键盘连接已变化，正在同步最新状态"
        case .cancellationTimedOut: return "键盘连接清理超时，等待系统释放接口"
        }
    }

    private func hex(_ status: IOReturn) -> String {
        "0x" + String(UInt32(bitPattern: status), radix: 16)
    }
}

public struct HIDConnectionIdentity: Equatable, Sendable {
    public let sessionID: UUID
    public let deviceID: UInt64
    public let selectionID: UUID

    public init(sessionID: UUID, deviceID: UInt64, selectionID: UUID = UUID()) {
        self.sessionID = sessionID
        self.deviceID = deviceID
        self.selectionID = selectionID
    }
}

public enum NuPhyHIDDeliveryState: Equatable, Sendable {
    case ready(HIDConnectionIdentity)
    case rebuilding
    case recovering(NuPhyHIDError)
}

public enum NuPhyHIDConnectionState: Equatable, Sendable {
    case disconnected
    case connected(productName: String, delivery: NuPhyHIDDeliveryState)
    case unavailable(NuPhyHIDError)
}

enum NuPhyHIDDeviceProfile: Int, Equatable, Sendable {
    case halo75V2USB = 0
    case halo75V2Bluetooth = 1
    case air60V2Bluetooth = 2
    case aulaF99ProBluetooth = 3
}

public final class NuPhyHIDTransport: @unchecked Sendable {
    static var deviceMatchingProperties: [[String: Any]] {
        [
            [
                kIOHIDTransportKey as String: "Bluetooth Low Energy",
                kIOHIDDeviceUsagePageKey as String: 1,
                kIOHIDDeviceUsageKey as String: 6,
            ],
            [
                kIOHIDVendorIDKey as String: 0x19F5,
                kIOHIDProductIDKey as String: 0x32F5,
            ],
        ]
    }

    public let connectionStates: AsyncStream<NuPhyHIDConnectionState>

    private let queue = DispatchQueue(label: "com.maige.NuphyBar.HID")
    private let queueKey = DispatchSpecificKey<Bool>()
    private let stateContinuation: AsyncStream<NuPhyHIDConnectionState>.Continuation
    private let makeManager: HIDManagerFactory
    private let checkAccess: @Sendable () -> NuPhyHIDAccessState
    private let diagnostics: RecoveryDiagnostics
    private let schedule: @Sendable (DispatchQueue, TimeInterval, DispatchWorkItem) -> Void
    private var manager: (any HIDManagerSession)?
    private var activeSessionID: UUID?
    private var lastAULASuccess: (connection: HIDConnectionIdentity, command: AgentLightCommand, time: TimeInterval)?
    private var cancellingSessionID: UUID?
    private struct SelectedDevice {
        let device: any HIDDeviceHandle
        let profile: NuPhyHIDDeviceProfile
        let identity: HIDConnectionIdentity
    }
    private var selectedDevice: SelectedDevice?
    private var recoveryProductName: String?
    private var currentState: NuPhyHIDConnectionState?
    private var reconnectBackoff = HIDReconnectBackoff()
    private var restartWorkItem: DispatchWorkItem?
    private var pendingRestartDelay: TimeInterval?
    private var cancellationWatchdog: DispatchWorkItem?
    private var isStopped = false

    public convenience init() {
        self.init(checkAccess: { Self.accessState }, diagnostics: .shared, makeManager: { queue, callbacks in
            try SystemHIDManager(queue: queue, callbacks: callbacks)
        })
    }

    init(checkAccess: @escaping @Sendable () -> NuPhyHIDAccessState,
         diagnostics: RecoveryDiagnostics = RecoveryDiagnostics(),
         makeManager: @escaping HIDManagerFactory,
         schedule: @escaping @Sendable (DispatchQueue, TimeInterval, DispatchWorkItem) -> Void = {
             queue, delay, item in queue.asyncAfter(deadline: .now() + delay, execute: item)
         }) {
        self.checkAccess = checkAccess
        self.diagnostics = diagnostics
        self.makeManager = makeManager
        self.schedule = schedule
        let stream = AsyncStream<NuPhyHIDConnectionState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        connectionStates = stream.stream
        stateContinuation = stream.continuation
        queue.setSpecific(key: queueKey, value: true)
        queue.sync { startManager() }
    }

    deinit {
        stateContinuation.finish()
        if DispatchQueue.getSpecific(key: queueKey) == true {
            stopManager()
        } else {
            queue.sync { stopManager() }
        }
    }

    private func stopManager() {
        isStopped = true
        restartWorkItem?.cancel()
        restartWorkItem = nil
        pendingRestartDelay = nil
        cancellationWatchdog?.cancel()
        cancelManager()
    }

    public static var accessState: NuPhyHIDAccessState {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .unknown
        }
    }

    @discardableResult
    public static func requestAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func isCompatible(
        productName: String?,
        transport: String?,
        maxOutputReportSize: Int?,
        usagePage: Int? = nil,
        usage: Int? = nil,
        vendorID: Int? = nil,
        productID: Int? = nil
    ) -> Bool {
        profile(
            productName: productName,
            transport: transport,
            maxOutputReportSize: maxOutputReportSize,
            usagePage: usagePage,
            usage: usage,
            vendorID: vendorID,
            productID: productID
        ) != nil
    }

    static func profile(
        productName: String?,
        transport: String?,
        maxOutputReportSize: Int?,
        usagePage: Int?,
        usage: Int?,
        vendorID: Int?,
        productID: Int?
    ) -> NuPhyHIDDeviceProfile? {
        guard let productName, let maxOutputReportSize else { return nil }

        let normalizedProductName = productName.trimmingCharacters(in: .whitespacesAndNewlines)

        if transport == "Bluetooth Low Energy",
           normalizedProductName.caseInsensitiveCompare("AULA-F99Pro 5.0") == .orderedSame,
           vendorID == 0x3554,
           productID == 0xFA07,
           usagePage == 0x01,
           usage == 0x06,
           maxOutputReportSize >= AULAF99ProRealtimeProtocol.reportLength {
            return .aulaF99ProBluetooth
        }

        guard normalizedProductName.range(
            of: "NuPhy",
            options: [.anchored, .caseInsensitive]
        ) != nil else { return nil }

        if transport == "USB",
           normalizedProductName.caseInsensitiveCompare("NuPhy Halo75 V2 NuphyBar") == .orderedSame,
           vendorID == 0x19F5,
           productID == 0x32F5,
           usagePage == 0xFF60,
           usage == 0x61,
           maxOutputReportSize >= Halo75V2RawHIDProtocol.reportLength {
            return .halo75V2USB
        }

        if transport == "Bluetooth Low Energy",
           maxOutputReportSize >= 2,
           vendorID == 0x19F5 {
            if productID == 0x3246,
               isBluetoothProduct(normalizedProductName, model: "Halo75 V2") {
                return .halo75V2Bluetooth
            }
            if isBluetoothProduct(normalizedProductName, model: "Air60 V2") {
                return .air60V2Bluetooth
            }
        }
        return nil
    }

    private static func isBluetoothProduct(_ productName: String, model: String) -> Bool {
        let baseName = "NuPhy \(model)"
        if productName.caseInsensitiveCompare(baseName) == .orderedSame {
            return true
        }
        for channel in 1...3 where
            productName.caseInsensitiveCompare("\(baseName)-\(channel)") == .orderedSame {
            return true
        }
        return false
    }

    public func refresh() {
        queue.async { [weak self] in
            self?.refreshManager()
        }
    }

    public var connectionState: NuPhyHIDConnectionState? {
        queue.sync { currentState }
    }

    public func rebuildSession() {
        queue.async { [weak self] in
            self?.rebuildManagerSession()
        }
    }

    public func describe() throws -> String {
        try queue.sync {
            guard let selectedDevice else {
                throw NuPhyHIDError.deviceNotConnected
            }
            let device = selectedDevice.device
            let name = productName(of: device)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "compatible keyboard"
            let transport = transport(of: device) ?? "unknown"
            let maxOutput = maxOutputReportSize(of: device)
            let reportDescription: String
            switch selectedDevice.profile {
            case .halo75V2USB:
                reportDescription = "Raw HID output, report ID 0"
            case .aulaF99ProBluetooth:
                reportDescription = "AULA real-time RGB output, report ID 0x13"
            default:
                reportDescription = "Keyboard LED output, report ID 1"
            }
            return [
                "Device: \(name)",
                "Transport: \(transport)",
                "Protocol: \(reportDescription)",
                "Max output report size: \(maxOutput.map(String.init) ?? "unknown") bytes",
            ].joined(separator: "\n")
        }
    }

    @discardableResult
    public func send(_ command: AgentLightCommand,
                     expectedConnection: HIDConnectionIdentity? = nil) throws -> HIDConnectionIdentity {
        try AgentLightTransmissionLock().withLock {
            try queue.sync {
                guard checkAccess() == .granted else {
                    refreshManager()
                    throw NuPhyHIDError.permissionDenied
                }
                guard let selectedDevice else {
                    throw NuPhyHIDError.deviceNotConnected
                }
                if let expectedConnection, expectedConnection != selectedDevice.identity {
                    throw NuPhyHIDError.connectionChanged
                }
                let currentDevice = selectedDevice.device

                do {
                    switch selectedDevice.profile {
                    case .halo75V2USB:
                        try setRawOutputReport(
                            Halo75V2RawHIDProtocol.encode(command),
                            on: currentDevice
                        )
                    case .halo75V2Bluetooth, .air60V2Bluetooth:
                        let capsLockOn = CGEventSource.flagsState(.combinedSessionState)
                            .contains(.maskAlphaShift)
                        let mask = DirectStatusEncoder.encode(command, capsLockOn: capsLockOn)
                        try setKeyboardLEDOutputReport(mask, on: currentDevice)
                    case .aulaF99ProBluetooth:
                        try setOutputReport(
                            AULAF99ProRealtimeProtocol.encode(command),
                            reportID: AULAF99ProRealtimeProtocol.reportID,
                            on: currentDevice
                        )
                    }
                    reconnectBackoff.reset()
                    let timestamp = ProcessInfo.processInfo.systemUptime
                    let logSuccess = selectedDevice.profile != .aulaF99ProBluetooth
                        || lastAULASuccess?.connection != selectedDevice.identity
                        || lastAULASuccess?.command != command
                        || timestamp - (lastAULASuccess?.time ?? 0) >= 60
                    if logSuccess {
                        if selectedDevice.profile == .aulaF99ProBluetooth {
                            lastAULASuccess = (selectedDevice.identity, command, timestamp)
                        }
                        diagnostics.record("hid.write.accepted", fields: [
                            "connection": selectedDevice.identity.selectionID.uuidString,
                            "profile": String(describing: selectedDevice.profile),
                            "command": String(describing: command),
                        ])
                    }
                    return selectedDevice.identity
                } catch let error as NuPhyHIDError {
                    diagnostics.record("hid.write.failed", fields: ["error": error.description,
                        "connection": selectedDevice.identity.selectionID.uuidString])
                    if selectedDevice.profile != .aulaF99ProBluetooth || error != .reportFailed(kIOReturnNotPermitted) {
                        recoverFromReportFailure(error, productName: productName(of: currentDevice))
                    }
                    throw error
                }
            }
        }
    }

    private func startManager() {
        guard !isStopped, manager == nil, cancellingSessionID == nil else { return }
        guard checkAccess() == .granted else {
            publish(.unavailable(.permissionDenied))
            return
        }

        let sessionID = UUID()
        let callbacks = HIDSessionCallbacks(
            matched: { [weak self] device in self?.handleMatchedDevice(device, sessionID: sessionID) },
            removed: { [weak self] device in self?.handleRemovedDevice(device, sessionID: sessionID) },
            cancelled: { [weak self] in self?.managerDidCancel(sessionID: sessionID) }
        )
        let manager: any HIDManagerSession
        do {
            manager = try makeManager(queue, callbacks)
        } catch {
            publish(.unavailable(error as? NuPhyHIDError ?? .managerOpenFailed(kIOReturnError)))
            scheduleManagerStart(after: reconnectBackoff.nextDelay())
            return
        }

        self.manager = manager
        activeSessionID = sessionID
        manager.activate()
        selectConnectedDevice(from: manager, sessionID: sessionID)
    }

    private func refreshManager() {
        guard checkAccess() == .granted else {
            recoveryProductName = nil
            selectedDevice = nil
            reconnectBackoff.reset()
            pendingRestartDelay = nil
            restartWorkItem?.cancel()
            restartWorkItem = nil
            cancelManager()
            publish(.unavailable(.permissionDenied))
            return
        }

        reconnectBackoff.reset()
        if cancellingSessionID != nil {
            pendingRestartDelay = 0
        } else if let manager, let activeSessionID {
            selectConnectedDevice(from: manager, sessionID: activeSessionID)
        } else {
            restartWorkItem?.cancel()
            restartWorkItem = nil
            startManager()
        }
    }

    private func rebuildManagerSession() {
        guard !isStopped else { return }
        guard checkAccess() == .granted else {
            refreshManager()
            return
        }

        restartWorkItem?.cancel()
        restartWorkItem = nil
        reconnectBackoff.reset()

        let connectedProductName = selectedDevice.flatMap { productName(of: $0.device) }
        selectedDevice = nil
        if let productName = connectedProductName ?? recoveryProductName {
            recoveryProductName = productName
            publish(.connected(productName: productName, delivery: .rebuilding))
        }

        if cancellingSessionID != nil {
            pendingRestartDelay = 0
            return
        } else if manager != nil {
            pendingRestartDelay = 0
            cancelManager()
        } else {
            pendingRestartDelay = nil
            startManager()
        }
    }

    private func selectConnectedDevice(from manager: any HIDManagerSession, sessionID: UUID) {
        guard activeSessionID == sessionID else { return }
        let devices = manager.devices
        if let selectedDevice, !devices.contains(where: { $0.identifier == selectedDevice.device.identifier }) {
            self.selectedDevice = nil
        }
        guard let device = devices
                .filter(isCompatible)
                .min(by: { profile(of: $0).rawValue < profile(of: $1).rawValue }) else {
            selectedDevice = nil
            recoveryProductName = nil
            publish(.disconnected)
            return
        }
        handleMatchedDevice(device, sessionID: sessionID)
    }

    private func handleMatchedDevice(_ device: any HIDDeviceHandle, sessionID: UUID) {
        guard activeSessionID == sessionID, let matchedProfile = optionalProfile(of: device) else { return }
        if let selectedDevice, let manager,
           !manager.devices.contains(where: { $0.identifier == selectedDevice.device.identifier }) {
            self.selectedDevice = nil
        }
        if let selectedDevice {
            if selectedDevice.device.identifier == device.identifier { return }
            if selectedDevice.profile.rawValue <= matchedProfile.rawValue { return }
        }

        let wasRecovering = recoveryProductName != nil
        let identity = HIDConnectionIdentity(sessionID: sessionID, deviceID: device.identifier)
        selectedDevice = SelectedDevice(device: device, profile: matchedProfile, identity: identity)
        recoveryProductName = nil
        if !wasRecovering {
            reconnectBackoff.reset()
        }
        publish(.connected(
            productName: productName(of: device)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "兼容键盘",
            delivery: .ready(identity)
        ))
    }

    private func handleRemovedDevice(_ device: any HIDDeviceHandle, sessionID: UUID) {
        guard activeSessionID == sessionID,
              let selectedDevice,
              selectedDevice.device.identifier == device.identifier else { return }
        self.selectedDevice = nil
        recoveryProductName = nil
        reconnectBackoff.reset()
        if let manager {
            selectConnectedDevice(from: manager, sessionID: sessionID)
            return
        }
        publish(.disconnected)
    }

    private func recoverFromReportFailure(_ error: NuPhyHIDError, productName: String?) {
        let productName = productName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "兼容键盘"
        recoveryProductName = productName
        selectedDevice = nil
        publish(.connected(
            productName: productName,
            delivery: .recovering(error)
        ))
        pendingRestartDelay = reconnectBackoff.nextDelay()
        cancelManager()
    }

    private func cancelManager() {
        guard let manager, let activeSessionID else { return }
        self.manager = nil
        self.activeSessionID = nil
        selectedDevice = nil
        cancellingSessionID = activeSessionID
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self, self.cancellingSessionID == activeSessionID, !self.isStopped else { return }
            self.publish(.unavailable(.cancellationTimedOut))
        }
        cancellationWatchdog?.cancel()
        cancellationWatchdog = watchdog
        schedule(queue, 10, watchdog)
        manager.cancel()
    }

    private func managerDidCancel(sessionID: UUID) {
        guard cancellingSessionID == sessionID else { return }
        cancellationWatchdog?.cancel()
        cancellationWatchdog = nil
        cancellingSessionID = nil
        guard let delay = pendingRestartDelay, !isStopped else { return }
        pendingRestartDelay = nil
        scheduleManagerStart(after: delay)
    }

    private func scheduleManagerStart(after delay: TimeInterval) {
        guard !isStopped else { return }
        restartWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.restartWorkItem = nil
            self.startManager()
        }
        restartWorkItem = workItem
        schedule(queue, delay, workItem)
    }

    private func publish(_ state: NuPhyHIDConnectionState) {
        guard state != currentState else { return }
        currentState = state
        diagnostics.record("hid.connection", fields: ["state": String(describing: state)])
        stateContinuation.yield(state)
    }

    private func isCompatible(_ device: any HIDDeviceHandle) -> Bool {
        optionalProfile(of: device) != nil
    }

    private func profile(of device: any HIDDeviceHandle) -> NuPhyHIDDeviceProfile {
        optionalProfile(of: device)!
    }

    private func optionalProfile(of device: any HIDDeviceHandle) -> NuPhyHIDDeviceProfile? {
        Self.profile(
            productName: productName(of: device),
            transport: transport(of: device),
            maxOutputReportSize: maxOutputReportSize(of: device),
            usagePage: device.properties.usagePage,
            usage: device.properties.usage,
            vendorID: device.properties.vendorID,
            productID: device.properties.productID
        )
    }

    private func productName(of device: any HIDDeviceHandle) -> String? {
        device.properties.productName
    }

    private func transport(of device: any HIDDeviceHandle) -> String? {
        device.properties.transport
    }

    private func maxOutputReportSize(of device: any HIDDeviceHandle) -> Int? {
        device.properties.maxOutputReportSize
    }

    private func setKeyboardLEDOutputReport(_ mask: UInt8, on device: any HIDDeviceHandle) throws {
        try device.send([1, mask], reportID: 1)
    }

    private func setRawOutputReport(_ report: [UInt8], on device: any HIDDeviceHandle) throws {
        try setOutputReport(report, reportID: 0, on: device)
    }

    private func setOutputReport(
        _ report: [UInt8],
        reportID: CFIndex,
        on device: any HIDDeviceHandle
    ) throws {
        try device.send(report, reportID: reportID)
    }
}
