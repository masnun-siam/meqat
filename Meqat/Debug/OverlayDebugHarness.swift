#if DEBUG
    import AppKit
    import MeqatCore

    @objc(MeqatDebugOverlayHarness)
    final class OverlayDebugHarness: NSObject, DebugHarness {
        private static let controller = MainActor.assumeIsolated { OverlayController() }

        /// Shows Asr (a Start overlay, no kind line) after 3 s, then Maghrib with the planner's End-alert kind line
        /// at lead 15 ("Maghrib ends in 15 min") 20 s later to test replacement. Names and the kind line follow
        /// the launch language, so `-AppleLanguages '(bn)'` shows them in Bangla.
        /// `-MeqatDebugHold <n>` overrides the 10 s timeout.
        static func run() {
            let override = UserDefaults.standard.integer(forKey: "MeqatDebugHold")
            let hold = UserDefaults.standard.object(forKey: "MeqatDebugHold") == nil ? 10 : override
            let language = Language.resolve(override: nil, preferred: Locale.preferredLanguages)
            @MainActor func fire(_ id: EventID, _ kindLine: String? = nil) {
                let now = Date()
                controller.show(
                    OverlayContent(
                        eventName: id.displayName(in: language), start: now, end: now.addingTimeInterval(7200), timeoutSeconds: hold,
                        timeFormat: .twentyFour, kindLine: kindLine, language: language))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { MainActor.assumeIsolated { fire(.asr) } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 23) {
                MainActor.assumeIsolated { fire(.maghrib, maghribEndLine(language)) }
            }
        }

        /// The overlay line `AlertPlanner` writes for a Maghrib End alert at lead 15, so the harness shows its real wording.
        private static func maghribEndLine(_ language: Language) -> String? {
            let now = Date()
            let interval = DateInterval(start: now, end: now.addingTimeInterval(7200))
            let event = ScheduledEvent(
                id: .maghrib, date: LocalDate(now, timeZone: .current), interval: interval, calculatedInterval: interval)
            var settings = AppSettings()
            settings.events[.maghrib] = EventSettings(
                startAlert: StartAlert(style: .disabled), endAlert: LeadAlert(style: .fullScreen, leadMinutes: 15))
            return AlertPlanner.plan(events: [event], settings: settings, now: now, timeZone: .current, language: language)
                .first { $0.kind == .end }?.overlayLine
        }
    }
#endif
