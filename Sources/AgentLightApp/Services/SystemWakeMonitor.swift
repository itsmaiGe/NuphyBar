@preconcurrency import AppKit

@MainActor
final class SystemWakeMonitor {
    private let center: NotificationCenter
    private var observer: NSObjectProtocol?

    init(
        center: NotificationCenter = NSWorkspace.shared.notificationCenter,
        notification: Notification.Name = NSWorkspace.didWakeNotification,
        handler: @escaping @MainActor @Sendable () -> Void
    ) {
        self.center = center
        observer = center.addObserver(
            forName: notification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                handler()
            }
        }
    }

    deinit {
        if let observer {
            center.removeObserver(observer)
        }
    }
}
