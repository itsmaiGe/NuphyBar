@preconcurrency import AppKit

@MainActor
final class SystemLifecycleMonitor {
    private let center: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    init(
        center: NotificationCenter = NSWorkspace.shared.notificationCenter,
        resumeHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        self.center = center
        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                resumeHandler()
            }
        })
    }

    deinit {
        for observer in observers {
            center.removeObserver(observer)
        }
    }
}
