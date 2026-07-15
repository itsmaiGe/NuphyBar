import IOKit.hid
import Testing
@testable import AgentLightHID

@Test("HID failures expose useful macOS error descriptions")
func localizedHIDError() {
    #expect(NuPhyHIDError.deviceNotConnected.localizedDescription
            == "未找到已连接的 NuphyBar 兼容 NuPhy 键盘")
    #expect(NuPhyHIDError.permissionDenied.localizedDescription
            == "需要允许 NuphyBar 访问键盘 HID 接口")
}

@Test("the HID manager only enumerates Bluetooth keyboards")
func scopedDeviceMatching() {
    let matching = NuPhyHIDTransport.deviceMatchingProperties
    #expect(matching[kIOHIDTransportKey as String] as? String == "Bluetooth Low Energy")
    #expect(matching[kIOHIDDeviceUsagePageKey as String] as? Int == 1)
    #expect(matching[kIOHIDDeviceUsageKey as String] as? Int == 6)
    #expect(matching[kIOHIDProductKey as String] == nil)
}

@Test("compatible NuPhy models are selected by family and HID capability")
func compatibleNuPhyKeyboards() {
    #expect(NuPhyHIDTransport.isCompatible(
        productName: "NuPhy Air60 V2-1",
        transport: "Bluetooth Low Energy",
        maxOutputReportSize: 2
    ))
    #expect(NuPhyHIDTransport.isCompatible(
        productName: "NuPhy Halo75 V2",
        transport: "Bluetooth Low Energy",
        maxOutputReportSize: 8
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
    #expect(!NuPhyHIDTransport.isCompatible(
        productName: "NuPhy Air60 V2-1",
        transport: "Bluetooth Low Energy",
        maxOutputReportSize: 1
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
