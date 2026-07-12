import AgentLightCore
import CoreGraphics
import Foundation
import IOKit.hid

public enum Air60HIDError: Error, CustomStringConvertible {
    case managerOpenFailed(IOReturn)
    case deviceNotConnected
    case deviceOpenFailed(IOReturn)
    case reportFailed(IOReturn)

    public var description: String {
        switch self {
        case .managerOpenFailed(let status): return "could not open the HID manager (0x\(String(status, radix: 16)))"
        case .deviceNotConnected: return "NuPhy Air60 V2-1 is not connected over Bluetooth"
        case .deviceOpenFailed(let status): return "could not open the keyboard (0x\(String(status, radix: 16)))"
        case .reportFailed(let status): return "sending a keyboard report failed (0x\(String(status, radix: 16)))"
        }
    }
}

public final class Air60HIDTransport {
    public static let productName = "NuPhy Air60 V2-1"
    private let bitInterval: TimeInterval

    private let wakeInterval: TimeInterval

    public init(bitInterval: TimeInterval = 0.030, wakeInterval: TimeInterval = 0.250) {
        self.bitInterval = bitInterval
        self.wakeInterval = wakeInterval
    }

    public func describe() throws -> String {
        try withDevice { device in
            let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
            let maxOutput = IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString)
                .flatMap { $0 as? NSNumber }?.intValue
            return [
                "Device: \(Self.productName)",
                "Transport: \(transport ?? "unknown")",
                "Output report: 1",
                "Max output report size: \(maxOutput.map(String.init) ?? "unknown") bytes",
            ].joined(separator: "\n")
        }
    }

    public func send(_ command: AgentLightCommand) throws {
        let capsLockOn = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
        let frame = WireFrame.encode(command)
        let masks = HIDReportEncoder.encode(frame, capsLockOn: capsLockOn)
        let capsMask: UInt8 = capsLockOn ? 0x02 : 0x00

        try withDevice { device in
            for (index, mask) in masks.enumerated() {
                try setOutputReport(mask, on: device)
                Thread.sleep(forTimeInterval: index < 2 ? wakeInterval : bitInterval)
            }
            Thread.sleep(forTimeInterval: 0.030)
            try setOutputReport(capsMask, on: device)
        }
    }

    private func withDevice<T>(_ operation: (IOHIDDevice) throws -> T) throws -> T {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        let managerStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerStatus == kIOReturnSuccess else {
            throw Air60HIDError.managerOpenFailed(managerStatus)
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first(where: { candidate in
                  IOHIDDeviceGetProperty(candidate, kIOHIDProductKey as CFString) as? String == Self.productName
              }) else {
            throw Air60HIDError.deviceNotConnected
        }

        let deviceStatus = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard deviceStatus == kIOReturnSuccess else {
            throw Air60HIDError.deviceOpenFailed(deviceStatus)
        }
        defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        return try operation(device)
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
            throw Air60HIDError.reportFailed(status)
        }
    }
}
