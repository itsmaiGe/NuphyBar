import Foundation
import IOKit.hid

struct HIDDeviceProperties: Sendable {
    var productName: String?
    var transport: String?
    var maxOutputReportSize: Int?
    var usagePage: Int?
    var usage: Int?
    var vendorID: Int?
    var productID: Int?
}

protocol HIDDeviceHandle: AnyObject, Sendable {
    var identifier: UInt64 { get }
    var properties: HIDDeviceProperties { get }
    func send(_ report: [UInt8], reportID: CFIndex) throws
}

struct HIDSessionCallbacks: Sendable {
    let matched: @Sendable (any HIDDeviceHandle) -> Void
    let removed: @Sendable (any HIDDeviceHandle) -> Void
    let cancelled: @Sendable () -> Void
}

protocol HIDManagerSession: AnyObject, Sendable {
    var devices: [any HIDDeviceHandle] { get }
    func activate()
    func cancel()
}

typealias HIDManagerFactory = @Sendable (
    DispatchQueue, HIDSessionCallbacks
) throws -> any HIDManagerSession

final class SystemHIDDevice: HIDDeviceHandle, @unchecked Sendable {
    private let device: IOHIDDevice

    init(_ device: IOHIDDevice) { self.device = device }

    var identifier: UInt64 {
        UInt64(UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque()))
    }

    var properties: HIDDeviceProperties {
        HIDDeviceProperties(
            productName: IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String,
            transport: IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String,
            maxOutputReportSize: integer(kIOHIDMaxOutputReportSizeKey),
            usagePage: integer(kIOHIDPrimaryUsagePageKey),
            usage: integer(kIOHIDPrimaryUsageKey),
            vendorID: integer(kIOHIDVendorIDKey),
            productID: integer(kIOHIDProductIDKey)
        )
    }

    private func integer(_ key: String) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }

    func send(_ report: [UInt8], reportID: CFIndex) throws {
        let status = report.withUnsafeBufferPointer { bytes in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, reportID, bytes.baseAddress!, bytes.count)
        }
        guard status == kIOReturnSuccess else { throw NuPhyHIDError.reportFailed(status) }
    }
}

final class SystemHIDManager: HIDManagerSession, @unchecked Sendable {
    private let manager: IOHIDManager

    init(queue: DispatchQueue, callbacks: HIDSessionCallbacks) throws {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, NuPhyHIDTransport.deviceMatchingProperties as CFArray)
        let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else { throw NuPhyHIDError.managerOpenFailed(status) }

        let context = CallbackContext(manager: manager, callbacks: callbacks)
        let pointer = Unmanaged.passUnretained(context).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, _, device in
            guard result == kIOReturnSuccess, let context else { return }
            Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue()
                .callbacks.matched(SystemHIDDevice(device))
        }, pointer)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue()
                .callbacks.removed(SystemHIDDevice(device))
        }, pointer)
        IOHIDManagerSetDispatchQueue(manager, queue)
        IOHIDManagerSetCancelHandler(manager) { [context] in
            _ = IOHIDManagerClose(context.manager, IOOptionBits(kIOHIDOptionsTypeNone))
            context.callbacks.cancelled()
        }
    }

    var devices: [any HIDDeviceHandle] {
        (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []).map { SystemHIDDevice($0) }
    }

    func activate() { IOHIDManagerActivate(manager) }
    func cancel() { IOHIDManagerCancel(manager) }

    private final class CallbackContext: @unchecked Sendable {
        let manager: IOHIDManager
        let callbacks: HIDSessionCallbacks

        init(manager: IOHIDManager, callbacks: HIDSessionCallbacks) {
            self.manager = manager
            self.callbacks = callbacks
        }
    }
}
