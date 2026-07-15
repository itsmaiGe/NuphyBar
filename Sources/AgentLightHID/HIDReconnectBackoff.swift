import Foundation

struct HIDReconnectBackoff {
    private static let delays: [TimeInterval] = [1, 2, 5, 10, 30]
    private var attempt = 0

    mutating func nextDelay() -> TimeInterval {
        let delay = Self.delays[min(attempt, Self.delays.count - 1)]
        attempt += 1
        return delay
    }

    mutating func reset() {
        attempt = 0
    }
}
