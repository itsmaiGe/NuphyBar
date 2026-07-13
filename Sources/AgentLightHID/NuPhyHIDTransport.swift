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

public enum NuPhyHIDError: LocalizedError, CustomStringConvertible {
    case permissionDenied
    case managerOpenFailed(IOReturn)
    case deviceNotConnected
    case deviceOpenFailed(IOReturn)
    case reportFailed(IOReturn)

    public var description: String {
        switch self {
        case .permissionDenied: return "keyboard HID access has not been granted"
        case .managerOpenFailed(let status): return "could not open the HID manager (\(hex(status)))"
        case .deviceNotConnected: return "no compatible NuPhy Bluetooth keyboard is connected"
        case .deviceOpenFailed(let status): return "could not open the NuPhy keyboard (\(hex(status)))"
        case .reportFailed(let status): return "sending a keyboard report failed (\(hex(status)))"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: return "需要允许 NuphyBar 访问键盘 HID 接口"
        case .managerOpenFailed: return "无法访问 macOS HID 设备管理器"
        case .deviceNotConnected: return "未找到已连接的 NuphyBar 兼容 NuPhy 键盘"
        case .deviceOpenFailed: return "无法打开 NuPhy 键盘；设备可能正在重新连接"
        case .reportFailed: return "无法向 NuPhy 键盘发送灯光状态"
        }
    }

    private func hex(_ status: IOReturn) -> String {
        "0x" + String(UInt32(bitPattern: status), radix: 16)
    }
}

public final class NuPhyHIDTransport {
    static var deviceMatchingProperties: [String: Any] {
        [
            kIOHIDTransportKey as String: "Bluetooth Low Energy",
            kIOHIDDeviceUsagePageKey as String: 1,
            kIOHIDDeviceUsageKey as String: 6,
        ]
    }

    public init() {}

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

    public func describe() throws -> String {
        try AgentLightTransmissionLock().withLock {
            try withDevice { device in
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
    }

    public func connectedProductName() throws -> String {
        try AgentLightTransmissionLock().withLock {
            try withDevice { device in
                productName(of: device) ?? "NuPhy 键盘"
            }
        }
    }

    public func send(_ command: AgentLightCommand) throws {
        try AgentLightTransmissionLock().withLock {
            let capsLockOn = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
            let mask = DirectStatusEncoder.encode(command, capsLockOn: capsLockOn)

            try withDevice { device in
                try setOutputReport(mask, on: device)
            }
        }
    }

    private func withDevice<T>(_ operation: (IOHIDDevice) throws -> T) throws -> T {
        guard Self.accessState == .granted else {
            throw NuPhyHIDError.permissionDenied
        }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, Self.deviceMatchingProperties as CFDictionary)
        let managerStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerStatus == kIOReturnSuccess else {
            throw NuPhyHIDError.managerOpenFailed(managerStatus)
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first(where: isCompatible) else {
            throw NuPhyHIDError.deviceNotConnected
        }

        let deviceStatus = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard deviceStatus == kIOReturnSuccess else {
            throw NuPhyHIDError.deviceOpenFailed(deviceStatus)
        }
        defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        return try operation(device)
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
}
