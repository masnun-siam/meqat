import XCTest

@testable import MeqatCore

final class MenuPresenterTests: XCTestCase {
    private let tz = TimeZone(identifier: "Asia/Dhaka")!
    private func d(_ day: Int) -> LocalDate { LocalDate(year: 2026, month: 10, day: day) }

    private func at(_ day: Int, _ h: Int, _ m: Int, _ s: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m, second: s))!
    }

    private func ev(
        _ id: EventID, _ day: Int, _ from: (Int, Int)?, _ to: (Int, Int)?, toDay: Int? = nil, prev: Bool = false, fromDay: Int? = nil
    ) -> ScheduledEvent {
        let i = from.flatMap { f in to.map { DateInterval(start: at(fromDay ?? day, f.0, f.1), end: at(toDay ?? day, $0.0, $0.1)) } }
        return ScheduledEvent(id: id, date: d(day), interval: i, calculatedInterval: i, startsPreviousNight: prev)
    }

    /// The FR-15 mockup day.
    private func mockup(_ day: Int = 28) -> [ScheduledEvent] {
        [
            ev(.tahajjud, day, (1, 0), (4, 52)), ev(.fajr, day, (4, 52), (6, 5)), ev(.shuruq, day, (6, 5), (6, 20)),
            ev(.duha, day, (6, 20), (11, 36)), ev(.istiwa, day, (11, 36), (11, 46)), ev(.dhuhr, day, (11, 46), (15, 4)),
            ev(.asr, day, (15, 4), (17, 12)), ev(.ghurub, day, (17, 12), (17, 27)), ev(.maghrib, day, (17, 27), (18, 42)),
            ev(.isha, day, (18, 42), (23, 59)),
        ]
    }

    private func present(_ now: Date, events: [ScheduledEvent]? = nil, _ tweak: (inout MenuInput) -> Void = { _ in }) -> MenuState {
        var input = MenuInput(now: now, timeZone: tz, events: events ?? mockup(), styles: [.duha: .disabled])
        tweak(&input)
        return MenuPresenter.present(input)
    }

    func testNextCountdownAndRows() {
        let s = present(at(28, 13, 52, 30))
        XCTAssertEqual(s.statusTitle, "☾ Dhuhr ends in 1h 11m")
        XCTAssertEqual(s.rows.count, 10)
        XCTAssertEqual(s.rows.map(\.marker), [.done, .done, .prohibited, .done, .prohibited, .current, .next, .prohibited, .none, .none])
        XCTAssertEqual(s.rows[5].detailText, "ends in 1h 11m")
        XCTAssertEqual(s.rows[6].detailText, "1h 11m")
        XCTAssertEqual(s.rows[2].isDimmed, true)
        XCTAssertEqual(s.rows[2].timeText, "06:05–06:20")
        XCTAssertEqual(s.header, "Wed 28 Oct")
    }

    func testDisabledDuhaSkippedButHasRow() {
        let s = present(at(28, 6, 20))
        XCTAssertEqual(s.statusTitle, "☾ Forbidden (noon) in 5h 16m")
        XCTAssertEqual(s.rows[3].id, .duha)
        XCTAssertEqual(s.rows[3].marker, .current)
    }

    func testProhibitedWinsEvenWhenDisabled() {
        let s = present(at(28, 11, 40)) {
            $0.styles[.istiwa] = .disabled
            $0.bannerNow = .asr
        }
        XCTAssertEqual(s.statusTitle, "⛔ Forbidden (noon) ends in 6m")
        XCTAssertEqual(s.statusAccessibilityLabel, "Forbidden (noon), forbidden window, ends in 6 minutes")
        XCTAssertEqual(present(at(28, 11, 47)).statusTitle, "☾ Dhuhr ends in 3h 17m")
    }

    func testAllDisabledShowsCrescent() {
        let s = present(at(28, 12, 0)) { i in EventID.allCases.forEach { i.styles[$0] = .disabled } }
        XCTAssertEqual(s.statusTitle, "☾")
        XCTAssertEqual(s.statusAccessibilityLabel, "Meqat")
    }

    func testCountdownRounding() {
        XCTAssertTrue(present(at(28, 15, 3, 1), events: [ev(.asr, 28, (15, 4), (17, 0))]).statusTitle.hasSuffix("Asr in <1m"))
        XCTAssertTrue(present(at(28, 14, 4), events: [ev(.asr, 28, (15, 4), (17, 0))]).statusTitle.hasSuffix("Asr in 1h 0m"))
        XCTAssertTrue(present(at(28, 14, 52), events: [ev(.asr, 28, (15, 4), (17, 0))]).statusTitle.hasSuffix("Asr in 12m"))
    }

    func testAfterIshaNextIsTomorrow() {
        let events = mockup(28) + mockup(29)
        XCTAssertEqual(present(at(28, 23, 59, 30), events: events).statusTitle, "☾ Tahajjud in 1h 0m")
        let s = present(at(28, 23, 59, 30), events: events) { $0.styles[.tahajjud] = .disabled }
        XCTAssertEqual(s.statusTitle, "☾ Fajr in 4h 52m")
    }

    func testDisabledCurrentFallsBackToNext() {
        let s = present(at(28, 16, 0)) { $0.styles[.asr] = .disabled }
        XCTAssertEqual(s.statusTitle, "☾ Forbidden (sunset) in 1h 12m")
    }

    func testLatestStartWinsAmongOverlappingCurrent() {
        let events = [ev(.isha, 28, (18, 42), (23, 59)), ev(.tahajjud, 28, (22, 0), (23, 30))]
        XCTAssertEqual(present(at(28, 22, 30), events: events).statusTitle, "☾ Tahajjud ends in 1h 0m")
    }

    func testEventAtExactEndIsNotCurrent() {
        XCTAssertEqual(present(at(28, 15, 4)).statusTitle, "☾ Asr ends in 2h 8m")
    }

    func testBannerNow() {
        XCTAssertEqual(present(at(28, 15, 5)) { $0.bannerNow = .asr }.statusTitle, "● Asr now")
        XCTAssertEqual(present(at(28, 15, 5)) { $0.bannerNow = .asr }.statusAccessibilityLabel, "Asr, now")
    }

    func testVoiceOverLabels() {
        let s = present(at(28, 13, 52, 30)) { $0.styles = [:] }
        XCTAssertEqual(s.rows[0].accessibilityLabel, "Tahajjud, done, 01:00")
        XCTAssertEqual(s.rows[4].accessibilityLabel, "Forbidden (noon), forbidden window, 11:36 to 11:46")
        XCTAssertEqual(s.rows[5].accessibilityLabel, "Dhuhr, current, 11:46, ends in 1 hour 11 minutes")
        XCTAssertEqual(s.rows[6].accessibilityLabel, "Asr, next, 15:04, in 1 hour 11 minutes")
        XCTAssertEqual(s.statusAccessibilityLabel, "Dhuhr, current, ends in 1 hour 11 minutes")
    }

    func testInvalidEventRow() {
        var events = mockup()
        events[3] = ev(.duha, 28, nil, nil)
        let s = present(at(28, 6, 0), events: events)
        XCTAssertEqual(s.rows[3].timeText, "—")
        XCTAssertEqual(s.rows[3].accessibilityLabel, "Duha, no time today")
        XCTAssertEqual(s.rows[3].marker, .none)
    }

    func testPrevNightLabelAndCarryOver() {
        let tomorrow = mockup(29).map { $0.id == .tahajjud ? ev(.tahajjud, 29, (23, 30), (4, 52), toDay: 30, prev: true, fromDay: 28) : $0 }
        // Tomorrow's list labels it.
        let next = present(at(29, 12, 0), events: tomorrow)
        XCTAssertEqual(next.rows[0].timeText, "23:30 (prev. night)")
        // Before midnight today's Tahajjud row is the carried event, current.
        let today = mockup(28) + tomorrow
        let before = present(at(28, 23, 40), events: today)
        XCTAssertEqual(before.rows[0].marker, .current)
        XCTAssertEqual(before.rows[0].timeText, "23:30")
        XCTAssertEqual(present(at(28, 23, 0), events: today).rows[0].marker, .done)
    }

    func testIshaStillCurrentInYesterdaysListAfterMidnight() {
        let yesterday = ev(.isha, 28, (18, 42), (1, 0), toDay: 29)
        let s = present(at(29, 0, 30), events: [yesterday] + mockup(29))
        XCTAssertEqual(s.rows.count, 10)
        XCTAssertFalse(s.rows.contains { $0.id == .isha && $0.marker == .current })
        XCTAssertEqual(s.rows[0].marker, .next)
    }

    func testEmptyStatePrecedence() {
        func state(_ loc: MenuLocationInfo, fetching: Bool = false, failure: MenuFailure? = nil) -> MenuEmptyState? {
            present(at(28, 12, 0)) {
                $0.hasScheduleForToday = false
                $0.location = loc
                $0.sync = MenuSyncInfo(isFetching: fetching, lastFailure: failure)
            }.emptyState
        }
        XCTAssertEqual(state(.awaitingPermission, fetching: true), .awaitingPermission)
        XCTAssertEqual(state(.awaitingFix, failure: .other), .fetching)
        XCTAssertEqual(state(.missing, fetching: true), .fetching)
        XCTAssertEqual(state(.missing, failure: .other), .setLocation)
        XCTAssertEqual(state(.available, failure: .cityNotFound), .cityNotFound)
        XCTAssertEqual(state(.available, failure: .other), .offline)
        XCTAssertEqual(state(.available), .fetching)
        XCTAssertEqual(MenuEmptyState.offline.action, .tryAgain)
        XCTAssertNil(MenuEmptyState.fetching.action)
        XCTAssertEqual(MenuEmptyState.setLocation.action, .openLocationPane)
        let s = present(at(28, 12, 0)) { $0.hasScheduleForToday = false }
        XCTAssertEqual(s.statusTitle, "☾")
        XCTAssertTrue(s.rows.isEmpty)
        XCTAssertNil(MenuPresenter.present(MenuInput(now: at(28, 12, 0), timeZone: tz, events: mockup())).emptyState)
    }

    func testTwelveHourFormat() {
        let s = present(at(28, 13, 52, 30)) {
            $0.timeFormat = .twelve
            $0.sync = MenuSyncInfo(lastSuccess: at(28, 15, 4))
        }
        XCTAssertEqual(s.rows[2].timeText, "6:05 AM–6:20 AM")
        XCTAssertEqual(s.rows[4].timeText, "11:36 AM–11:46 AM")
        XCTAssertTrue(s.rows[0].accessibilityLabel.hasSuffix("1:00 AM"), s.rows[0].accessibilityLabel)
        XCTAssertEqual(s.footerStatus, "Synced 3:04 PM")
        let other = present(at(28, 12, 0)) {
            $0.timeFormat = .twelve
            $0.sync = MenuSyncInfo(lastSuccess: at(27, 15, 4))
        }
        XCTAssertEqual(other.footerStatus, "Synced 27 Oct 3:04 PM")
    }

    func testFooterVariants() {
        func footer(_ sync: MenuSyncInfo, couldnt: Bool = false) -> (String, Bool) {
            let s = present(at(28, 12, 0)) {
                $0.sync = sync
                $0.showsCouldntRefresh = couldnt
            }
            return (s.footerStatus, s.refreshEnabled)
        }
        XCTAssertEqual(footer(MenuSyncInfo(lastSuccess: at(28, 9, 5))).0, "Synced 09:05")
        XCTAssertEqual(footer(MenuSyncInfo(lastSuccess: at(27, 9, 5))).0, "Synced 27 Oct 09:05")
        XCTAssertEqual(footer(MenuSyncInfo(isFetching: true, lastSuccess: at(28, 9, 5))).0, "Syncing…")
        XCTAssertFalse(footer(MenuSyncInfo(isFetching: true)).1)
        XCTAssertEqual(footer(MenuSyncInfo(lastSuccess: at(27, 9, 5), offlineSince: at(28, 8, 0))).0, "Offline — using cache from 27 Oct")
        let failed = footer(MenuSyncInfo(isFetching: true), couldnt: true)
        XCTAssertEqual(failed.0, "Couldn't refresh")
        XCTAssertFalse(failed.1)
        XCTAssertEqual(footer(MenuSyncInfo()).0, "")
    }

    func testNotificationsOffRowAndPlace() {
        let s = present(at(28, 12, 0)) {
            $0.notificationsAuthorized = false
            $0.place = "Dhaka"
        }
        XCTAssertTrue(s.showsNotificationsOffRow)
        XCTAssertEqual(s.header, "Wed 28 Oct · Dhaka")
    }
}
