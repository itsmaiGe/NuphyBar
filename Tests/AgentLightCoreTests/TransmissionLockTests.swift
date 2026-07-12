import Dispatch
import Foundation
import Testing
@testable import AgentLightCore

@Test("separate senders cannot transmit at the same time")
func transmissionLockSerializesSenders() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "transmission.lock")
    let firstEntered = DispatchSemaphore(value: 0)
    let releaseFirst = DispatchSemaphore(value: 0)
    let secondEntered = DispatchSemaphore(value: 0)

    DispatchQueue.global().async {
        try! AgentLightTransmissionLock(url: url).withLock { () -> Void in
            firstEntered.signal()
            releaseFirst.wait()
        }
    }
    #expect(firstEntered.wait(timeout: .now() + 1) == .success)

    DispatchQueue.global().async {
        try! AgentLightTransmissionLock(url: url).withLock { () -> Void in
            secondEntered.signal()
        }
    }
    #expect(secondEntered.wait(timeout: .now() + 0.1) == .timedOut)
    releaseFirst.signal()
    #expect(secondEntered.wait(timeout: .now() + 1) == .success)
}
