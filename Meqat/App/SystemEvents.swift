import AppKit

/// Sleep, wake, clock, time zone and quit notifications, forwarded as closures.
@MainActor
final class SystemEvents {
    struct Handlers {
        var willSleep: @MainActor () -> Void
        var didWake: @MainActor () -> Void
        var timeZoneChanged: @MainActor () -> Void
        var clockChanged: @MainActor () -> Void
        var willTerminate: @MainActor () -> Void
    }

    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    init(_ handlers: Handlers) {
        let workspace = NSWorkspace.shared.notificationCenter
        add(workspace, NSWorkspace.willSleepNotification, handlers.willSleep)
        add(workspace, NSWorkspace.didWakeNotification, handlers.didWake)
        add(.default, .NSSystemTimeZoneDidChange) {
            NSTimeZone.resetSystemTimeZone()
            handlers.timeZoneChanged()
        }
        add(.default, .NSSystemClockDidChange, handlers.clockChanged)
        add(.default, NSApplication.willTerminateNotification, handlers.willTerminate)
    }

    deinit {
        for (center, token) in tokens { center.removeObserver(token) }
    }

    private func add(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        tokens.append((center, token))
    }
}
