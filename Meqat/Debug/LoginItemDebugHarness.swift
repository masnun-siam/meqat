#if DEBUG
import AppKit
import MeqatCore
import ServiceManagement

/// `--args -MeqatDebugHarness LoginItem`: applies the stored launchAtLogin setting and prints the status.
@objc(MeqatDebugLoginItemHarness)
final class LoginItemDebugHarness: NSObject, DebugHarness {
    static func run() {
        MainActor.assumeIsolated {
            let wanted = SettingsStore().settings.general.launchAtLogin
            let error = LoginItemSync.apply(wanted, to: MainAppLoginItem())
            print("launchAtLogin=\(wanted) status=\(SMAppService.mainApp.status) error=\(error.map { "\($0)" } ?? "none")")
        }
    }
}
#endif
