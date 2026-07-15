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

@Test("Antigravity camel-case hooks preserve active work and completion")
func antigravityHookMapping() throws {
    let invocation = Data(#"{"conversationId":"agy-1"}"#.utf8)
    let activeStop = Data(#"{"conversationId":"agy-1","fullyIdle":false,"terminationReason":"model_stop","error":""}"#.utf8)
    let completeStop = Data(#"{"conversationId":"agy-1","fullyIdle":true,"terminationReason":"model_stop","error":""}"#.utf8)
    let errorStop = Data(#"{"conversationId":"agy-1","fullyIdle":true,"terminationReason":"error","error":"boom"}"#.utf8)

    #expect(try HookEventMapper.map(provider: .antigravity, eventName: "PreInvocation", payload: invocation)?.status == .working)
    #expect(try HookEventMapper.map(provider: .antigravity, eventName: "Stop", payload: activeStop)?.status == .working)
    #expect(try HookEventMapper.map(provider: .antigravity, eventName: "Stop", payload: completeStop)?.status == .complete)
    #expect(try HookEventMapper.map(provider: .antigravity, eventName: "Stop", payload: errorStop)?.status == .error)
}

@Test("Antigravity hooks return non-invasive responses required by Google")
func antigravityHookResponses() throws {
    let invocation = try #require(HookEventMapper.response(provider: .antigravity, eventName: "PreInvocation"))
    let stop = try #require(HookEventMapper.response(provider: .antigravity, eventName: "Stop"))

    #expect(try JSONSerialization.jsonObject(with: invocation) as? [String: String] == [:])
    #expect((try JSONSerialization.jsonObject(with: stop) as? [String: String])?["decision"] == "stop")
    #expect(HookEventMapper.response(provider: .codex, eventName: "Stop") == nil)
}

@Test("unknown hooks are ignored and malformed payloads are rejected")
func unknownAndMalformedHooks() throws {
    let payload = Data(#"{"session_id":"one"}"#.utf8)
    #expect(try HookEventMapper.map(provider: .codex, eventName: "Unrelated", payload: payload) == nil)
    #expect(throws: HookEventError.invalidPayload) {
        try HookEventMapper.map(provider: .codex, eventName: "Stop", payload: Data("{}".utf8))
    }
}
