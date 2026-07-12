import Testing
@testable import AgentLightCore

@Test("progress commands produce a versioned frame with a valid checksum")
func progressFrame() throws {
    let encoded = WireFrame.encode(.progress(3))

    #expect(encoded.prefix(6) == [0xA7, 0xD3, 0x01, 0x20, 0x01, 0x03])
    #expect(try WireFrame.decode(encoded) == .progress(3))
}

@Test("the HID clock toggles for every bit and preserves Caps Lock")
func hidBitEncoding() {
    let frame = WireFrame.encode(.working)
    let reports = HIDReportEncoder.encode(frame, capsLockOn: true)

    #expect(reports.count == 1 + frame.count * 8)
    #expect(reports.allSatisfy { $0 & 0x02 == 0x02 })
    #expect(reports.first! & 0x05 == 0)

    for index in 2..<reports.count {
        #expect((reports[index] ^ reports[index - 1]) & 0x04 == 0x04)
    }
}

@Test("a corrupted frame is rejected")
func corruptedFrame() {
    var encoded = WireFrame.encode(.color(red: 12, green: 34, blue: 56))
    encoded[encoded.count - 2] ^= 0x01

    #expect(throws: WireProtocolError.invalidChecksum) {
        try WireFrame.decode(encoded)
    }
}

@Test("completion duration is carried as a compact firmware setting")
func completionDurationFrame() throws {
    let encoded = WireFrame.encode(.completionDuration(seconds: 12))

    #expect(try WireFrame.decode(encoded) == .completionDuration(seconds: 12))
}

@Test("frequent status commands use an eight-report BLE frame")
func compactStatusFrame() {
    let reports = CompactStatusEncoder.encode(.progress(3), capsLockOn: true)

    #expect(reports?.count == 8)
    #expect(reports?.allSatisfy { $0 & 0x02 == 0x02 } == true)
    #expect(reports == [0x02, 0x03, 0x06, 0x07, 0x02, 0x07, 0x06, 0x02])
    #expect(CompactStatusEncoder.encode(.color(red: 1, green: 2, blue: 3), capsLockOn: false) == nil)
}
