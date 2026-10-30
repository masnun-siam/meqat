import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var environment: AppEnvironment?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
            if DebugHarnessLauncher.runIfRequested() { return }
        #endif
        UNUserNotificationCenter.current().delegate = self
        let environment = AppEnvironment()
        environment.start()
        self.environment = environment
    }

    /// Shows banners while Meqat is frontmost, as it is when the Settings window sends the test banner.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
