#if DEBUG
    import AppKit

    @objc(MeqatDebugOverlayHarness)
    final class OverlayDebugHarness: NSObject, DebugHarness {
        private static let controller = MainActor.assumeIsolated { OverlayController() }

        /// Shows "Asr" after 3 s, then "Maghrib" 20 s later to test replacement.
        /// `-MeqatDebugHold <n>` overrides the 10 s hold.
        static func run() {
            let override = UserDefaults.standard.integer(forKey: "MeqatDebugHold")
            let hold = UserDefaults.standard.object(forKey: "MeqatDebugHold") == nil ? 10 : override
            @MainActor func fire(_ name: String) {
                let now = Date()
                controller.show(OverlayContent(eventName: name, start: now, end: now.addingTimeInterval(7200), holdSeconds: hold))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { MainActor.assumeIsolated { fire("Asr") } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 23) { MainActor.assumeIsolated { fire("Maghrib") } }
        }
    }
#endif
