#if DEBUG
    import AppKit
    import MeqatCore

    @objc(MeqatDebugOverlayHarness)
    final class OverlayDebugHarness: NSObject, DebugHarness {
        private static let controller = MainActor.assumeIsolated { OverlayController() }

        /// Shows "Asr" (a Start overlay, no kind line) after 3 s, then "Maghrib" with the kind line
        /// "Maghrib ends in 15 min" 20 s later to test replacement.
        /// `-MeqatDebugHold <n>` overrides the 10 s timeout.
        static func run() {
            let override = UserDefaults.standard.integer(forKey: "MeqatDebugHold")
            let hold = UserDefaults.standard.object(forKey: "MeqatDebugHold") == nil ? 10 : override
            @MainActor func fire(_ name: String, _ kindLine: String? = nil) {
                let now = Date()
                controller.show(
                    OverlayContent(
                        eventName: name, start: now, end: now.addingTimeInterval(7200), timeoutSeconds: hold, timeFormat: .twentyFour,
                        kindLine: kindLine, language: Language.resolve(override: nil, preferred: Locale.preferredLanguages)))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { MainActor.assumeIsolated { fire("Asr") } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 23) { MainActor.assumeIsolated { fire("Maghrib", "Maghrib ends in 15 min") } }
        }
    }
#endif
