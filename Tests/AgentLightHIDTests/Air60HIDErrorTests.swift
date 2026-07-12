import Testing
@testable import AgentLightHID

@Test("HID failures expose a useful macOS error description")
func localizedHIDError() {
    #expect(Air60HIDError.deviceNotConnected.localizedDescription
            == "NuPhy Air60 V2-1 未通过蓝牙连接")
}
