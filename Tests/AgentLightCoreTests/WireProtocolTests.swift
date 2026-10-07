import Testing
@testable import AgentLightCore

@Test("agent states use one persistent BLE LED report")
func directStatusReport() {
    #expect(DirectStatusEncoder.encode(.idle, capsLockOn: true) == 0x02)
    #expect(DirectStatusEncoder.encode(.working, capsLockOn: true) == 0x03)
    #expect(DirectStatusEncoder.encode(.toolRunning, capsLockOn: true) == 0x03)
    #expect(DirectStatusEncoder.encode(.outputting, capsLockOn: true) == 0x03)
    #expect(DirectStatusEncoder.encode(.waiting, capsLockOn: true) == 0x06)
    #expect(DirectStatusEncoder.encode(.complete, capsLockOn: true) == 0x07)
    #expect(DirectStatusEncoder.encode(.error, capsLockOn: false) == 0x04)
}

@Test("Halo75 V2 Raw HID reports expose every rich state")
func halo75V2RawHIDReport() {
    let expectedCodes: [(AgentLightCommand, UInt8)] = [
        (.idle, 0),
        (.working, 1),
        (.toolRunning, 2),
        (.outputting, 3),
        (.waiting, 4),
        (.complete, 5),
        (.error, 6),
    ]

    for (command, stateCode) in expectedCodes {
        let report = Halo75V2RawHIDProtocol.encode(command)
        #expect(report.count == 32)
        #expect(Array(report.prefix(4)) == [0x4E, 0x42, 0x01, 0x01])
        #expect(report[4] == stateCode)
        #expect(Halo75V2RawHIDProtocol.hasValidChecksum(report))
    }
}

@Test("AULA F99 Pro real-time reports expose every state without configuration writes")
func aulaF99ProRealtimeReport() {
    let expectedColors: [(AgentLightCommand, [UInt8])] = [
        (.working, [0xFF, 0x00, 0x00]),
        (.toolRunning, [0xFF, 0x00, 0x00]),
        (.outputting, [0xFF, 0xB0, 0x00]),
        (.waiting, [0x00, 0x66, 0xFF]),
        (.complete, [0x00, 0xFF, 0x00]),
        (.error, [0xFF, 0x00, 0x00]),
    ]

    for (command, color) in expectedColors {
        let report = AULAF99ProRealtimeProtocol.encode(command)
        #expect(report.count == 20)
        #expect(Array(report.prefix(5)) == [0x13, 0x88, 0x01, 0x00, 0x23])
        #expect(Array(report[5...7]) == color)
        #expect(AULAF99ProRealtimeProtocol.hasValidChecksum(report))
    }

    let idle = AULAF99ProRealtimeProtocol.encode(.idle)
    #expect(Array(idle.prefix(5)) == [0x13, 0x03, 0x00, 0x00, 0x00])
    #expect(AULAF99ProRealtimeProtocol.hasValidChecksum(idle))
}
