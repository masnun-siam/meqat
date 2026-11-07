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

    /// Lets a running update cancel its download or finish its swap before Meqat quits.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let environment, environment.needsQuitWait else { return .terminateNow }
        Task { @MainActor in
            await environment.prepareToQuit()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Shows banners while Meqat is frontmost, as it is when the Settings window sends the test banner.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
