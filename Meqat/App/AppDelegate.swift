import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        if DebugHarnessLauncher.runIfRequested() { return }
        #endif
        let environment = AppEnvironment()
        environment.start()
        self.environment = environment
    }
}
