#if DEBUG
    import AppKit

    @objc protocol DebugHarness {
        static func run()
    }

    enum DebugHarnessLauncher {
        /// Launch with `--args -MeqatDebugHarness Overlay` to run `MeqatDebugOverlayHarness`.
        /// Returns true when a harness ran, so the caller skips the placeholder status item.
        static func runIfRequested() -> Bool {
            guard let name = UserDefaults.standard.string(forKey: "MeqatDebugHarness"),
                let harness = NSClassFromString("MeqatDebug\(name)Harness") as? DebugHarness.Type
            else { return false }
            harness.run()
            return true
        }
    }
#endif
