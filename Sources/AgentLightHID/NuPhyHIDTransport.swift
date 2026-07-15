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

    public var description: String {
        switch self {
        case .permissionDenied: return "keyboard HID access has not been granted"
        case .managerOpenFailed(let status): return "could not open the HID manager (\(hex(status)))"
        case .deviceNotConnected: return "no compatible NuPhy Bluetooth keyboard is connected"
        case .reportFailed(let status): return "sending a keyboard report failed (\(hex(status)))"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: return "需要允许 NuphyBar 访问键盘 HID 接口"
        case .managerOpenFailed: return "无法访问 macOS HID 设备管理器"
        case .deviceNotConnected: return "未找到已连接的 NuphyBar 兼容 NuPhy 键盘"
        case .reportFailed: return "无法向 NuPhy 键盘发送灯光状态"
        }
    }

    private func hex(_ status: IOReturn) -> String {
        "0x" + String(UInt32(bitPattern: status), radix: 16)
    }
}

public enum NuPhyHIDDeliveryState: Equatable, Sendable {
    case ready
    case rebuilding
    case recovering(NuPhyHIDError)
}

public enum NuPhyHIDConnectionState: Equatable, Sendable {
    case disconnected
    case connected(productName: String, delivery: NuPhyHIDDeliveryState)
    case unavailable(NuPhyHIDError)
}

public final class NuPhyHIDTransport: @unchecked Sendable {
    static var deviceMatchingProperties: [String: Any] {
        [
            kIOHIDTransportKey as String: "Bluetooth Low Energy",
            kIOHIDDeviceUsagePageKey as String: 1,
            kIOHIDDeviceUsageKey as String: 6,
        ]
    }

    public let connectionStates: AsyncStream<NuPhyHIDConnectionState>

    private let queue = DispatchQueue(label: "com.maige.NuphyBar.HID")
    private let stateContinuation: AsyncStream<NuPhyHIDConnectionState>.Continuation
    private var manager: IOHIDManager?
    private var activeSessionID: UUID?
    private var cancellingSessionID: UUID?
    private var currentDevice: IOHIDDevice?
    private var recoveryProductName: String?
    private var currentState: NuPhyHIDConnectionState?
    private var reconnectBackoff = HIDReconnectBackoff()
    private var restartWorkItem: DispatchWorkItem?
    private var pendingRestartDelay: TimeInterval?
    private var isStopped = false

    public init() {
        let stream = AsyncStream<NuPhyHIDConnectionState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        connectionStates = stream.stream
        stateContinuation = stream.continuation
        queue.sync { startManager() }
    }

    deinit {
        stateContinuation.finish()
        queue.sync {
            isStopped = true
            restartWorkItem?.cancel()
            restartWorkItem = nil
            pendingRestartDelay = nil
            cancelManager()
        }
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
        maxOutputReportSize: Int?
    ) -> Bool {
        guard let productName,
              productName.range(of: "NuPhy", options: [.anchored, .caseInsensitive]) != nil,
              transport == "Bluetooth Low Energy",
              let maxOutputReportSize,
              maxOutputReportSize >= 2 else { return false }
        return true
    }

    public func refresh() {
        queue.async { [weak self] in
            self?.refreshManager()
        }
    }

    public func rebuildSession() {
        queue.async { [weak self] in
            self?.rebuildManagerSession()
        }
    }

    public func describe() throws -> String {
        try queue.sync {
            guard let device = currentDevice else {
                throw NuPhyHIDError.deviceNotConnected
            }
            let name = productName(of: device) ?? "NuPhy keyboard"
            let transport = transport(of: device) ?? "unknown"
            let maxOutput = maxOutputReportSize(of: device)
            return [
                "Device: \(name)",
                "Transport: \(transport)",
                "Output report: 1",
                "Max output report size: \(maxOutput.map(String.init) ?? "unknown") bytes",
            ].joined(separator: "\n")
        }
    }

    public func send(_ command: AgentLightCommand) throws {
        try AgentLightTransmissionLock().withLock {
            let capsLockOn = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
            let mask = DirectStatusEncoder.encode(command, capsLockOn: capsLockOn)

            try queue.sync {
                guard Self.accessState == .granted else {
                    refreshManager()
                    throw NuPhyHIDError.permissionDenied
                }
                guard let currentDevice else {
                    throw NuPhyHIDError.deviceNotConnected
                }

                do {
                    try setOutputReport(mask, on: currentDevice)
                    reconnectBackoff.reset()
                } catch let error as NuPhyHIDError {
                    recoverFromReportFailure(error, productName: productName(of: currentDevice))
                    throw error
                }
            }
        }
    }

    private func startManager() {
        guard !isStopped, manager == nil, cancellingSessionID == nil else { return }
        guard Self.accessState == .granted else {
            publish(.unavailable(.permissionDenied))
            return
        }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, Self.deviceMatchingProperties as CFDictionary)
        let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else {
            publish(.unavailable(.managerOpenFailed(status)))
            scheduleManagerStart(after: reconnectBackoff.nextDelay())
            return
        }

        let sessionID = UUID()
        let context = ManagerCallbackContext(owner: self, manager: manager, sessionID: sessionID)
        let contextPointer = Unmanaged.passUnretained(context).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(
            manager,
            Self.deviceMatchedCallback,
            contextPointer
        )
        IOHIDManagerRegisterDeviceRemovalCallback(
            manager,
            Self.deviceRemovedCallback,
            contextPointer
        )
        IOHIDManagerSetDispatchQueue(manager, queue)
        IOHIDManagerSetCancelHandler(manager) { [context] in
            _ = IOHIDManagerClose(context.manager, IOOptionBits(kIOHIDOptionsTypeNone))
            context.owner?.managerDidCancel(sessionID: context.sessionID)
        }

        self.manager = manager
        activeSessionID = sessionID
        IOHIDManagerActivate(manager)
        selectConnectedDevice(from: manager, sessionID: sessionID)
    }

    private func refreshManager() {
        guard Self.accessState == .granted else {
            recoveryProductName = nil
            currentDevice = nil
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
        guard Self.accessState == .granted else {
            refreshManager()
            return
        }

        restartWorkItem?.cancel()
        restartWorkItem = nil
        reconnectBackoff.reset()

        if let productName = currentDevice.flatMap(productName(of:)) ?? recoveryProductName {
            currentDevice = nil
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

    private func selectConnectedDevice(from manager: IOHIDManager, sessionID: UUID) {
        guard activeSessionID == sessionID else { return }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first(where: isCompatible) else {
            currentDevice = nil
            recoveryProductName = nil
            publish(.disconnected)
            return
        }
        handleMatchedDevice(device, sessionID: sessionID)
    }

    private func handleMatchedDevice(_ device: IOHIDDevice, sessionID: UUID) {
        guard activeSessionID == sessionID, isCompatible(device) else { return }
        if let currentDevice, CFEqual(currentDevice, device) { return }

        let wasRecovering = recoveryProductName != nil
        currentDevice = device
        recoveryProductName = nil
        if !wasRecovering {
            reconnectBackoff.reset()
        }
        publish(.connected(
            productName: productName(of: device) ?? "NuPhy 键盘",
            delivery: .ready
        ))
    }

    private func handleRemovedDevice(_ device: IOHIDDevice, sessionID: UUID) {
        guard activeSessionID == sessionID,
              let currentDevice,
              CFEqual(currentDevice, device) else { return }
        self.currentDevice = nil
        recoveryProductName = nil
        reconnectBackoff.reset()
        publish(.disconnected)
    }

    private func recoverFromReportFailure(_ error: NuPhyHIDError, productName: String?) {
        let productName = productName ?? "NuPhy 键盘"
        recoveryProductName = productName
        currentDevice = nil
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
        cancellingSessionID = activeSessionID
        IOHIDManagerCancel(manager)
    }

    private func managerDidCancel(sessionID: UUID) {
        guard cancellingSessionID == sessionID else { return }
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
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func publish(_ state: NuPhyHIDConnectionState) {
        guard state != currentState else { return }
        currentState = state
        stateContinuation.yield(state)
    }

    private func isCompatible(_ device: IOHIDDevice) -> Bool {
        Self.isCompatible(
            productName: productName(of: device),
            transport: transport(of: device),
            maxOutputReportSize: maxOutputReportSize(of: device)
        )
    }

    private func productName(of device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
    }

    private func transport(of device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
    }

    private func maxOutputReportSize(of device: IOHIDDevice) -> Int? {
        IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString)
            .flatMap { $0 as? NSNumber }?.intValue
    }

    private func setOutputReport(_ mask: UInt8, on device: IOHIDDevice) throws {
        var report: [UInt8] = [1, mask]
        let reportCount = report.count
        let status = report.withUnsafeMutableBytes { bytes in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                1,
                bytes.bindMemory(to: UInt8.self).baseAddress!,
                reportCount
            )
        }
        guard status == kIOReturnSuccess else {
            throw NuPhyHIDError.reportFailed(status)
        }
    }

    private static let deviceMatchedCallback: IOHIDDeviceCallback = {
        context, result, _, device in
        guard result == kIOReturnSuccess, let context else { return }
        let callbackContext = Unmanaged<ManagerCallbackContext>
            .fromOpaque(context).takeUnretainedValue()
        callbackContext.owner?.handleMatchedDevice(
            device,
            sessionID: callbackContext.sessionID
        )
    }

    private static let deviceRemovedCallback: IOHIDDeviceCallback = {
        context, _, _, device in
        guard let context else { return }
        let callbackContext = Unmanaged<ManagerCallbackContext>
            .fromOpaque(context).takeUnretainedValue()
        callbackContext.owner?.handleRemovedDevice(
            device,
            sessionID: callbackContext.sessionID
        )
    }

    private final class ManagerCallbackContext: @unchecked Sendable {
        weak var owner: NuPhyHIDTransport?
        let manager: IOHIDManager
        let sessionID: UUID

        init(owner: NuPhyHIDTransport, manager: IOHIDManager, sessionID: UUID) {
            self.owner = owner
            self.manager = manager
            self.sessionID = sessionID
        }
    }
}
