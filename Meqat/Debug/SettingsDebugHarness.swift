#if DEBUG
    import AppKit
    import MeqatCore

    /// `--args -MeqatDebugHarness Settings` opens the Settings window. Extra arguments:
    /// `-MeqatDebugPane <location|about|eventID>`, `-MeqatDebugWindows 1`,
    /// `-MeqatDebugLookup <idle|lookingUp|found|cityNotFound|unreachable>`,
    /// `-MeqatDebugUpdate <idle|checking|upToDate|available|installable|failed>` (`installable` is `available` with
    /// install possible), `-MeqatDebugInstall <downloading|installing|failed>` (implies `installable`).
    /// DEBUG builds never install, so this is the only way to see the install lines in About.
    @objc(MeqatDebugSettingsHarness)
    final class SettingsDebugHarness: NSObject, DebugHarness {
        static func run() {
            MainActor.assumeIsolated {
                let args = UserDefaults.standard
                let controller = SettingsWindowController.shared
                controller.store = SettingsStore()
                controller.context = makeContext(args)
                controller.show(pane: pane(args.string(forKey: "MeqatDebugPane")))
            }
        }

        @MainActor private static func makeContext(_ args: UserDefaults) -> SettingsContext {
            let context = SettingsContext()
            context.language = Language.resolve(override: nil, preferred: Locale.preferredLanguages)
            context.place = "Dhaka"
            context.coordinatesText = String(format: "%.2f, %.2f", locale: context.language.locale, 23.81, 90.41)
            let format = AppEnvironment.lastSyncFormat(.current, .twentyFour, context.language)
            context.lastSyncText = format.string(from: mockDate(day: 30, hour: 13, minute: 50))
            if args.bool(forKey: "MeqatDebugWindows") { context.calculatedWindows = mockupWindows() }
            switch args.string(forKey: "MeqatDebugLookup") {
            case "lookingUp": context.lookupStatus = .lookingUp
            case "found": context.lookupStatus = .found
            case "cityNotFound": context.lookupStatus = .cityNotFound
            case "unreachable": context.lookupStatus = .unreachable
            default: context.lookupStatus = .idle
            }
            context.lastCheckedText = format.string(from: mockDate(day: 30, hour: 9, minute: 5))
            let installState = args.string(forKey: "MeqatDebugInstall")
            func available(canInstall: Bool) -> UpdateStatus {
                .available(
                    version: "1.4.0", releaseURL: URL(string: "https://github.com/masnun-siam/meqat/releases/tag/v1.4.0")!,
                    canInstall: canInstall)
            }
            switch installState == nil ? args.string(forKey: "MeqatDebugUpdate") : "installable" {
            case "checking": context.updateStatus = .checking
            case "upToDate": context.updateStatus = .upToDate(checkedAt: Date())
            case "available": context.updateStatus = available(canInstall: false)
            case "installable": context.updateStatus = available(canInstall: true)
            case "failed": context.updateStatus = .failed
            default: context.updateStatus = .idle
            }
            switch installState {
            case "downloading": context.installState = .downloading(percent: 42)
            case "installing": context.installState = .installing
            case "failed": context.installState = .failed
            default: context.installState = .idle
            }
            context.checkNow = { context.updateStatus = .checking }
            context.install = { context.installState = .downloading(percent: 42) }
            context.cancelInstall = { context.installState = .idle }
            return context
        }

        private static func mockDate(day: Int, hour: Int, minute: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }

        private static func pane(_ name: String?) -> SettingsPane {
            guard let name else { return .general }
            if name == "location" { return .location }
            if name == "about" { return .about }
            return EventID(rawValue: name).map(SettingsPane.event) ?? .general
        }

        /// FR-15 mockup times for today.
        private static func mockupWindows() -> [EventID: DateInterval] {
            let times: [(EventID, String, String)] = [
                (.tahajjud, "03:41", "04:52"), (.fajr, "04:52", "06:05"), (.shuruq, "06:05", "06:20"),
                (.duha, "06:20", "11:36"), (.istiwa, "11:36", "11:46"), (.dhuhr, "11:46", "15:04"),
                (.jumah, "11:46", "15:04"), (.asr, "15:04", "17:27"), (.ghurub, "17:12", "17:27"),
                (.maghrib, "17:27", "18:42"), (.isha, "18:42", "23:48"),
            ]
            func date(_ hhmm: String) -> Date {
                let p = hhmm.split(separator: ":").compactMap { Int($0) }
                return Calendar.current.date(bySettingHour: p[0], minute: p[1], second: 0, of: Date())!
            }
            return Dictionary(uniqueKeysWithValues: times.map { ($0.0, DateInterval(start: date($0.1), end: date($0.2))) })
        }
    }
#endif
