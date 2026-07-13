import Testing
@testable import AgentLightCore

@Test("agent states use one persistent BLE LED report")
func directStatusReport() {
    #expect(DirectStatusEncoder.encode(.idle, capsLockOn: true) == 0x02)
    #expect(DirectStatusEncoder.encode(.working, capsLockOn: true) == 0x03)
    #expect(DirectStatusEncoder.encode(.waiting, capsLockOn: true) == 0x06)
    #expect(DirectStatusEncoder.encode(.complete, capsLockOn: true) == 0x07)
    #expect(DirectStatusEncoder.encode(.error, capsLockOn: false) == 0x04)
}
