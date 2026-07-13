import Foundation
import Testing
@testable import AgentLightCore

@Test("Grok Build accepts its camel-case hook payload")
func grokBuildCamelCasePayload() throws {
    let payload = Data(#"{"sessionId":"grok-session","hookEventName":"UserPromptSubmit"}"#.utf8)
    let mapped = try HookEventMapper.map(
        provider: .grokBuild,
        eventName: "UserPromptSubmit",
        payload: payload
    )
    let event = try #require(mapped)
    #expect(event.sessionID == "grok-session")
    #expect(event.status == .working)
}

@Test("Codex lifecycle hooks map to shared Agent Light states")
func codexHookMapping() throws {
    let payload = Data(#"{"session_id":"codex-1"}"#.utf8)

    #expect(try HookEventMapper.map(provider: .codex, eventName: "UserPromptSubmit", payload: payload)?.status == .working)
    #expect(try HookEventMapper.map(provider: .codex, eventName: "PermissionRequest", payload: payload)?.status == .waiting)
    #expect(try HookEventMapper.map(provider: .codex, eventName: "PostToolUse", payload: payload)?.status == .working)
    #expect(try HookEventMapper.map(provider: .codex, eventName: "Stop", payload: payload)?.status == .complete)
}

@Test("Claude only treats notifications that need user input as waiting")
func claudeHookMapping() throws {
    let needsInput = Data(#"{"session_id":"claude-1","notification_type":"agent_needs_input"}"#.utf8)
    let authSuccess = Data(#"{"session_id":"claude-1","notification_type":"auth_success"}"#.utf8)
    let payload = Data(#"{"session_id":"claude-1"}"#.utf8)

    #expect(try HookEventMapper.map(provider: .claudeCode, eventName: "Notification", payload: needsInput)?.status == .waiting)
    #expect(try HookEventMapper.map(provider: .claudeCode, eventName: "Notification", payload: authSuccess) == nil)
    #expect(try HookEventMapper.map(provider: .claudeCode, eventName: "PostToolUse", payload: payload)?.status == .working)
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
