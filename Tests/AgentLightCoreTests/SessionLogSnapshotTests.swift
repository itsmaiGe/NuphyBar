import Foundation
import Testing
@testable import AgentLightCore

@Test("Session log pages enforce their byte budget and snapshot version")
func sessionLogPages() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("0123456789\n".utf8).write(to: url)
    let version = try #require(SessionLogSnapshot.version(url: url))
    #expect(SessionLogSnapshot.page(url: url, version: version, limit: 4)?.data == Data("789\n".utf8))
    #expect(SessionLogSnapshot.page(url: url, version: version, offset: 0, limit: 4)?.data == Data("0123".utf8))
    let previous = try #require(SessionLogSnapshot.page(url: url, version: version, before: 7, limit: 4))
    #expect(previous.start == 3)
    #expect(previous.data == Data("3456".utf8))
    try Data("new snapshot\n".utf8).write(to: url, options: .atomic)
    #expect(SessionLogSnapshot.page(url: url, version: version, limit: 4) == nil)
}

@Test("Session log inspection rejects changes made while parsing")
func sessionLogChangesDuringParsing() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("original\n".utf8).write(to: url)
    let result: Bool? = SessionLogSnapshot.inspect(url: url) { _, _ in
        try Data("replacement\n".utf8).write(to: url, options: .atomic)
        return true
    }
    #expect(result == nil)
}
