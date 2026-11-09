import Dispatch
import Darwin
import Foundation
import Testing
@testable import AgentLightCore

@Test("spawned children cannot retain the transmission lock")
func transmissionLockClosesOnExec() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "transmission.lock")
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep")
    child.arguments = ["10"]
    defer {
        if child.isRunning { child.terminate() }
        child.waitUntilExit()
    }
    try AgentLightTransmissionLock(url: url).withLock {
        var expected = stat()
        #expect(lstat(url.path, &expected) == 0)
        let matches = (0..<getdtablesize()).filter { descriptor in
            var actual = stat()
            return fstat(descriptor, &actual) == 0
                && actual.st_dev == expected.st_dev && actual.st_ino == expected.st_ino
        }
        #expect(!matches.isEmpty)
        for descriptor in matches { #expect(fcntl(descriptor, F_GETFD) & FD_CLOEXEC != 0) }
        try child.run()
    }
    let start = ContinuousClock.now
    try AgentLightTransmissionLock(url: url).withLock { }
    #expect(start.duration(to: .now) < .seconds(2))
    #expect(child.isRunning)
}

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
