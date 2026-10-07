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

@Test("tool execution and output have distinct rich commands")
func richWorkingStates() {
    var state = AgentState()
    state.apply(.init(provider: .codex, sessionID: "one", status: .outputting), now: 100)
    #expect(state.displayCommand(now: 100) == .outputting)

    state.apply(.init(provider: .claudeCode, sessionID: "two", status: .toolRunning), now: 101)
    #expect(state.displayCommand(now: 101) == .toolRunning)
}

@Test("idle removes a session and terminal states are pruned")
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

@Test("active states remain until an explicit lifecycle event ends them")
func activeStatesDoNotExpire() {
    var state = AgentState()
    state.apply(.init(provider: .codex, sessionID: "one", status: .working), now: 100)

    let presentation = state.presentation(now: 100 + 24 * 60 * 60)
    #expect(presentation.command == .working)
    #expect(presentation.nextExpiration == nil)
}

@Test("an error is shown briefly and then returns to idle")
func errorExpiry() {
    var state = AgentState()
    state.apply(.init(provider: .antigravity, sessionID: "one", status: .error), now: 200)

    #expect(state.displayCommand(now: 200) == .error)
    #expect(state.displayCommand(now: 200 + AgentState.completionRetention + 1) == .idle)
}

@Test("state presentation schedules the earliest exact expiration")
func presentationSchedulesEarliestExpiration() {
    var state = AgentState()
    state.apply(.init(provider: .codex, sessionID: "working", status: .working), now: 100)
    state.apply(.init(provider: .claudeCode, sessionID: "complete", status: .complete), now: 200)

    let beforeExpiry = state.presentation(now: 201)
    #expect(beforeExpiry.command == .working)
    #expect(beforeExpiry.nextExpiration == 200 + AgentState.completionRetention + 1)

    let afterExpiry = state.presentation(now: 200 + AgentState.completionRetention + 1)
    #expect(afterExpiry.command == .working)
    #expect(afterExpiry.nextExpiration == nil)
}

@Test("an empty presentation has no expiration timer")
func emptyPresentationHasNoExpiration() {
    var state = AgentState()
    let presentation = state.presentation(now: 100)

    #expect(presentation.command == .idle)
    #expect(presentation.nextExpiration == nil)
}
