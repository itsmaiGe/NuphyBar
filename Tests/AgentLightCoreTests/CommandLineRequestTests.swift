import Testing
@testable import AgentLightCore

@Test("status commands map to wire commands")
func statusCommands() throws {
    #expect(try CommandLineRequest.parse(["working"]) == .send(.working))
    #expect(try CommandLineRequest.parse(["waiting"]) == .send(.waiting))
    #expect(try CommandLineRequest.parse(["complete"]) == .send(.complete))
    #expect(try CommandLineRequest.parse(["idle"]) == .send(.idle))
}

@Test("progress accepts exactly the five physical LED stages")
func progressCommand() throws {
    #expect(try CommandLineRequest.parse(["progress", "0"]) == .send(.progress(0)))
    #expect(try CommandLineRequest.parse(["progress", "5"]) == .send(.progress(5)))
    #expect(throws: CommandLineError.invalidProgress) {
        try CommandLineRequest.parse(["progress", "6"])
    }
}

@Test("color accepts a six-digit hexadecimal RGB value")
func colorCommand() throws {
    #expect(try CommandLineRequest.parse(["color", "#0C2238"])
            == .send(.color(red: 12, green: 34, blue: 56)))
    #expect(throws: CommandLineError.invalidColor) {
        try CommandLineRequest.parse(["color", "blue"])
    }
}

@Test("the CRC fixture is shared with the keyboard decoder")
func crcFixture() {
    #expect(WireFrame.crc8([0x01, 0x20, 0x01, 0x03]) == 0x49)
}

@Test("hook and explicit agent events identify their provider and session")
func agentEvents() throws {
    #expect(try CommandLineRequest.parse(["hook", "codex", "Stop"]) == .hook(.codex, "Stop"))
    #expect(try CommandLineRequest.parse(["event", "opencode", "working", "session-1"])
            == .event(.init(provider: .openCode, sessionID: "session-1", status: .working)))
    #expect(try CommandLineRequest.parse(["event", "opencode", "progress", "session-1", "4"])
            == .event(.init(provider: .openCode, sessionID: "session-1", status: .progress(4))))
}
