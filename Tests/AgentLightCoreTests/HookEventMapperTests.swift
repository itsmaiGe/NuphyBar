import Foundation
import Testing
@testable import AgentLightCore

@Test("Codex lifecycle hooks map to shared Agent Light states")
func codexHookMapping() throws {
    let payload = Data(#"{"session_id":"codex-1"}"#.utf8)

    #expect(try HookEventMapper.map(provider: .codex, eventName: "UserPromptSubmit", payload: payload)?.status == .working)
    #expect(try HookEventMapper.map(provider: .codex, eventName: "PermissionRequest", payload: payload)?.status == .waiting)
    #expect(try HookEventMapper.map(provider: .codex, eventName: "Stop", payload: payload)?.status == .complete)
}

@Test("Claude notification and session end events map without reading transcripts")
func claudeHookMapping() throws {
    let payload = Data(#"{"session_id":"claude-1"}"#.utf8)

    #expect(try HookEventMapper.map(provider: .claudeCode, eventName: "Notification", payload: payload)?.status == .waiting)
    #expect(try HookEventMapper.map(provider: .claudeCode, eventName: "SessionEnd", payload: payload)?.status == .idle)
}

@Test("unknown hooks are ignored and malformed payloads are rejected")
func unknownAndMalformedHooks() throws {
    let payload = Data(#"{"session_id":"one"}"#.utf8)
    #expect(try HookEventMapper.map(provider: .codex, eventName: "Unrelated", payload: payload) == nil)
    #expect(throws: HookEventError.invalidPayload) {
        try HookEventMapper.map(provider: .codex, eventName: "Stop", payload: Data("{}".utf8))
    }
}
