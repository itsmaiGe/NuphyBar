import Testing
@testable import AgentLightCore

@Test("a working session is not hidden by another session completing")
func workingBeatsComplete() {
    var state = AgentState()
    state.apply(.init(provider: .codex, sessionID: "one", status: .working), now: 100)
    state.apply(.init(provider: .claudeCode, sessionID: "two", status: .complete), now: 101)

    #expect(state.displayCommand(now: 101) == .working)
}

@Test("waiting and errors take priority over ordinary work")
func attentionPriorities() {
    var state = AgentState()
    state.apply(.init(provider: .codex, sessionID: "one", status: .working), now: 100)
    state.apply(.init(provider: .openCode, sessionID: "two", status: .waiting), now: 101)
    #expect(state.displayCommand(now: 101) == .waiting)

    state.apply(.init(provider: .claudeCode, sessionID: "three", status: .error), now: 102)
    #expect(state.displayCommand(now: 102) == .error)
}

@Test("explicit progress is shown when it is the only active task")
func explicitProgress() {
    var state = AgentState()
    state.apply(.init(provider: .openCode, sessionID: "one", status: .progress(4)), now: 100)

    #expect(state.displayCommand(now: 100) == .progress(4))
}

@Test("idle removes a session and expired states are pruned")
func idleAndExpiry() {
    var state = AgentState()
    let key = AgentSessionKey(provider: .codex, sessionID: "one")
    state.apply(.init(provider: .codex, sessionID: "one", status: .working), now: 100)
    #expect(state.sessions[key] != nil)

    state.apply(.init(provider: .codex, sessionID: "one", status: .idle), now: 101)
    #expect(state.sessions[key] == nil)

    state.apply(.init(provider: .claudeCode, sessionID: "two", status: .complete), now: 200)
    #expect(state.displayCommand(now: 200 + AgentState.completionRetention + 1) == .idle)
}
