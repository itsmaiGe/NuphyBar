import IOKit.hid
import Testing
@testable import AgentLightHID

@Test("HID failures expose useful macOS error descriptions")
func localizedHIDError() {
    #expect(NuPhyHIDError.deviceNotConnected.localizedDescription
            == "未找到已连接的 NuphyBar 兼容键盘")
    #expect(NuPhyHIDError.permissionDenied.localizedDescription
            == "需要允许 NuphyBar 访问键盘 HID 接口")
}

@Test("the HID manager broadly enumerates Halo75 V2 interfaces before strict filtering")
func scopedDeviceMatching() {
    let matching = NuPhyHIDTransport.deviceMatchingProperties
    #expect(matching.count == 2)

    let bluetooth = matching[0]
    #expect(bluetooth[kIOHIDTransportKey as String] as? String == "Bluetooth Low Energy")
    #expect(bluetooth[kIOHIDDeviceUsagePageKey as String] as? Int == 1)
    #expect(bluetooth[kIOHIDDeviceUsageKey as String] as? Int == 6)

    let rawHID = matching[1]
    #expect(rawHID[kIOHIDVendorIDKey as String] as? Int == 0x19F5)
    #expect(rawHID[kIOHIDProductIDKey as String] as? Int == 0x32F5)
    #expect(rawHID.count == 2)
}

@Test("compatible keyboard models are selected by exact identity and HID capability")
func compatibleKeyboards() {
    #expect(NuPhyHIDTransport.isCompatible(
        productName: "NuPhy Air60 V2-1",
        transport: "Bluetooth Low Energy",
        maxOutputReportSize: 2,
        vendorID: 0x19F5
    ))
    #expect(NuPhyHIDTransport.isCompatible(
        productName: "NuPhy Halo75 V2",
        transport: "Bluetooth Low Energy",
        maxOutputReportSize: 8,
        vendorID: 0x19F5,
        productID: 0x3246
    ))
    #expect(NuPhyHIDTransport.isCompatible(
        productName: "NuPhy Halo75 V2-3",
        transport: "Bluetooth Low Energy",
        maxOutputReportSize: 8,
        vendorID: 0x19F5,
        productID: 0x3246
    ))
    #expect(!NuPhyHIDTransport.isCompatible(
        productName: "NuPhy Air75 V2-1",
        transport: "Bluetooth Low Energy",
        maxOutputReportSize: 2,
        vendorID: 0x19F5
    ))
    #expect(!NuPhyHIDTransport.isCompatible(
        productName: "NuPhy Halo75 V2 prototype",
        transport: "Bluetooth Low Energy",
        maxOutputReportSize: 8,
        vendorID: 0x19F5,
        productID: 0x3246
    ))
    #expect(!NuPhyHIDTransport.isCompatible(
        productName: "NuPhy Halo75 V2-1",
        transport: "Bluetooth Low Energy",
        maxOutputReportSize: 8,
        vendorID: 0x05AC,
        productID: 0x3246
    ))
    #expect(!NuPhyHIDTransport.isCompatible(
        productName: "Apple Internal Keyboard / Trackpad",
        transport: "Bluetooth Low Energy",
        maxOutputReportSize: 2
    ))
    #expect(!NuPhyHIDTransport.isCompatible(
        productName: "NuPhy Air60 V2-1",
        transport: "USB",
        maxOutputReportSize: 2
    ))
    #expect(NuPhyHIDTransport.isCompatible(
        productName: "NuPhy Halo75 V2 NuphyBar",
        transport: "USB",
        maxOutputReportSize: 32,
        usagePage: 0xFF60,
        usage: 0x61,
        vendorID: 0x19F5,
        productID: 0x32F5
    ))
    #expect(!NuPhyHIDTransport.isCompatible(
        productName: "NuPhy Halo75 V2",
        transport: "USB",
        maxOutputReportSize: 32,
        usagePage: 0xFF60,
        usage: 0x61,
        vendorID: 0x19F5,
        productID: 0x32F5
    ))
    #expect(!NuPhyHIDTransport.isCompatible(
        productName: "NuPhy Halo75 V2 NuphyBar",
        transport: "USB",
        maxOutputReportSize: 32,
        usagePage: 1,
        usage: 6,
        vendorID: 0x19F5,
        productID: 0x32F5
    ))
    #expect(!NuPhyHIDTransport.isCompatible(
        productName: "NuPhy Air60 V2-1",
        transport: "Bluetooth Low Energy",
        maxOutputReportSize: 1,
        vendorID: 0x19F5
    ))
    #expect(NuPhyHIDTransport.isCompatible(
        productName: "AULA-F99Pro 5.0 ",
        transport: "Bluetooth Low Energy",
        maxOutputReportSize: 20,
        usagePage: 0x01,
        usage: 0x06,
        vendorID: 0x3554,
        productID: 0xFA07
    ))
    #expect(!NuPhyHIDTransport.isCompatible(
        productName: "AULA-F99Pro 5.0 ",
        transport: "Bluetooth Low Energy",
        maxOutputReportSize: 19,
        usagePage: 0x01,
        usage: 0x06,
        vendorID: 0x3554,
        productID: 0xFA07
    ))
    #expect(!NuPhyHIDTransport.isCompatible(
        productName: "AULA-F99Pro 5.0 ",
        transport: "Bluetooth Low Energy",
        maxOutputReportSize: 20,
        usagePage: 0x01,
        usage: 0x06,
        vendorID: 0x3554,
        productID: 0xFA09
    ))
    #expect(!NuPhyHIDTransport.isCompatible(
        productName: "AULA-F99Pro 3.0",
        transport: "Bluetooth Low Energy",
        maxOutputReportSize: 20,
        usagePage: 0x01,
        usage: 0x06,
        vendorID: 0x3554,
        productID: 0xFA07
    ))
}

@Test("HID recovery backs off and stays bounded until a report succeeds")
func boundedReconnectBackoff() {
    var backoff = HIDReconnectBackoff()

    #expect((0..<6).map { _ in backoff.nextDelay() } == [1, 2, 5, 10, 30, 30])

    backoff.reset()
    #expect(backoff.nextDelay() == 1)
}

@Test("report recovery does not pretend the keyboard was disconnected")
func recoveryKeepsKeyboardPresence() {
    let state = NuPhyHIDConnectionState.connected(
        productName: "NuPhy Air60 V2-1",
        delivery: .recovering(.reportFailed(kIOReturnNotPermitted))
    )

    guard case .connected(let productName, .recovering(let error)) = state else {
        Issue.record("expected a connected keyboard with a recovering report channel")
        return
    }
    #expect(productName == "NuPhy Air60 V2-1")
    #expect(error == .reportFailed(kIOReturnNotPermitted))
}

@Test("proactive HID session rebuilding keeps the keyboard present")
func rebuildingKeepsKeyboardPresence() {
    let state = NuPhyHIDConnectionState.connected(
        productName: "NuPhy Air60 V2-1",
        delivery: .rebuilding
    )

    guard case .connected(let productName, .rebuilding) = state else {
        Issue.record("expected a connected keyboard with a rebuilding report channel")
        return
    }
    #expect(productName == "NuPhy Air60 V2-1")
}
