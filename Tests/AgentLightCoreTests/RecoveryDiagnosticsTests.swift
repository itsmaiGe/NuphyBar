import Foundation
import Testing
@testable import AgentLightCore

@Test("recovery diagnostics retain only a bounded recent history")
func boundedRecoveryHistory() throws {
    let journal = RecoveryDiagnostics(capacity: 2)
    for index in 0..<4 { journal.record("event", fields: ["index": String(index)]) }
    let entries = try JSONDecoder().decode([RecoveryDiagnostics.Entry].self, from: journal.export())
    #expect(entries.count == 2)
    #expect(entries.first?.fields["index"] == "2")
}

@Test("helper and app diagnostics share a bounded persistent journal")
func sharedRecoveryHistory() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "diagnostics.json")
    let helper = RecoveryDiagnostics(url: url, capacity: 2)
    let app = RecoveryDiagnostics(url: url, capacity: 2)
    helper.record("hook.received")
    app.record("state.read")
    helper.record("state.persisted")
    let entries = try JSONDecoder().decode([RecoveryDiagnostics.Entry].self, from: app.export())
    #expect(entries.map(\.event) == ["state.read", "state.persisted"])
    let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    #expect(permissions == 0o600)
}

@Test("diagnostic identifiers are stable and do not contain the source identity")
func anonymizedRecoveryIdentity() {
    let id = RecoveryDiagnostics.anonymousID("private-session-id")
    #expect(id.count == 16)
    #expect(id == RecoveryDiagnostics.anonymousID("private-session-id"))
    #expect(id != RecoveryDiagnostics.anonymousID("different-session-id"))
}
