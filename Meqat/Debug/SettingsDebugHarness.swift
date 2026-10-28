#if DEBUG
    import AppKit
    import MeqatCore

    /// `--args -MeqatDebugHarness Settings` opens the Settings window. Extra arguments:
    /// `-MeqatDebugPane <location|eventID>`, `-MeqatDebugWindows 1`,
    /// `-MeqatDebugLookup <idle|lookingUp|found|cityNotFound|unreachable>`.
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
            context.place = "Dhaka"
            context.coordinatesText = "23.81, 90.41"
            context.lastSyncText = "Synced 13:50"
            if args.bool(forKey: "MeqatDebugWindows") { context.calculatedWindows = mockupWindows() }
            switch args.string(forKey: "MeqatDebugLookup") {
            case "lookingUp": context.lookupStatus = .lookingUp
            case "found": context.lookupStatus = .found
            case "cityNotFound": context.lookupStatus = .cityNotFound
            case "unreachable": context.lookupStatus = .unreachable
            default: context.lookupStatus = .idle
            }
            return context
        }

        private static func pane(_ name: String?) -> SettingsPane {
            guard let name else { return .general }
            if name == "location" { return .location }
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
