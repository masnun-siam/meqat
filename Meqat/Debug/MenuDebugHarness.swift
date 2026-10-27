#if DEBUG
import AppKit
import MeqatCore

/// `-MeqatDebugHarness Menu` shows the FR-15 mockup day; add `-MeqatDebugEmpty offline` for the empty state.
@objc(MeqatDebugMenuHarness)
final class MenuDebugHarness: NSObject, DebugHarness {
    private static var controller: StatusItemController?

    static func run() {
        MainActor.assumeIsolated {
            let tz = TimeZone.current
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz
            func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: Date())! }
            func ev(_ id: EventID, _ f: (Int, Int), _ t: (Int, Int)) -> ScheduledEvent {
                let day = LocalDate(year: cal.component(.year, from: Date()), month: cal.component(.month, from: Date()), day: cal.component(.day, from: Date()))
                let i = DateInterval(start: at(f.0, f.1), end: at(t.0, t.1))
                return ScheduledEvent(id: id, date: day, interval: i, calculatedInterval: i)
            }
            let events = [ev(.tahajjud, (1, 0), (4, 52)), ev(.fajr, (4, 52), (6, 5)), ev(.shuruq, (6, 5), (6, 20)),
                          ev(.duha, (6, 20), (11, 36)), ev(.istiwa, (11, 36), (11, 46)), ev(.dhuhr, (11, 46), (15, 4)),
                          ev(.asr, (15, 4), (17, 12)), ev(.ghurub, (17, 12), (17, 27)), ev(.maghrib, (17, 27), (18, 42)),
                          ev(.isha, (18, 42), (23, 59))]
            let empty = UserDefaults.standard.string(forKey: "MeqatDebugEmpty") == "offline"
            // Clock runs on from 13:52 so the title ticks.
            let offset = at(13, 52).timeIntervalSinceNow
            let synced = at(13, 50)
            func log(_ name: String) -> @MainActor () -> Void { { print("action:", name) } }
            let actions = MenuActions(refreshNow: log("refreshNow"), openSettings: log("openSettings"),
                                      openLocationPane: log("openLocationPane"), tryAgain: log("tryAgain"),
                                      dropdownOpened: log("dropdownOpened"))
            controller = StatusItemController(state: {
                MenuPresenter.present(MenuInput(
                    now: Date().addingTimeInterval(offset), timeZone: tz, events: events, styles: [.duha: .disabled], place: "Dhaka",
                    hasScheduleForToday: !empty, sync: MenuSyncInfo(lastSuccess: synced, lastFailure: empty ? .other : nil),
                    notificationsAuthorized: false))
            }, actions: actions)
        }
    }
}
#endif
