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
        XCTAssertEqual(s.rows.map(\.id), [.tahajjud, .fajr, .duha, .dhuhr, .asr, .maghrib, .isha])
        XCTAssertEqual(s.rows.map(\.marker), [.done, .done, .done, .current, .next, .none, .none])
        XCTAssertEqual(s.rows[2].timeText, "06:20–11:36")
        XCTAssertEqual(s.header, "Wed 28 Oct")
    }

    func testDisabledDuhaSkippedButHasRow() {
        let s = present(at(28, 6, 20))
        XCTAssertEqual(s.statusTitle, "☾ Forbidden (noon) in 5h 16m")
        XCTAssertEqual(s.rows[2].id, .duha)
        XCTAssertEqual(s.rows[2].marker, .current)
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

    func testAllOffEventLeavesNowNextAndReturnsWhenOneAlertIsOn() {
        // Styles built as AppEnvironment.menuState() does: the derived EventSettings.style.
        var dhuhr = EventSettings(startAlert: StartAlert(style: .disabled))
        let styles = { [EventID.duha: EventSettings.defaults(for: .duha).style, .dhuhr: dhuhr.style] }
        let off = present(at(28, 13, 52, 30)) { $0.styles = styles() }
        XCTAssertEqual(off.statusTitle, "☾ Asr in 1h 11m")
        XCTAssertEqual(off.hero?.kind, .next)
        XCTAssertEqual(off.hero?.title, "Next · Asr")
        dhuhr.endAlert.style = .banner
        let endOn = present(at(28, 13, 52, 30)) { $0.styles = styles() }
        XCTAssertEqual(endOn.statusTitle, "☾ Dhuhr ends in 1h 11m")
        XCTAssertEqual(endOn.hero?.kind, .current)
        XCTAssertEqual(endOn.hero?.title, "Dhuhr")
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
        XCTAssertEqual(s.rows[2].accessibilityLabel, "Duha, done, 06:20 to 11:36")
        XCTAssertEqual(s.rows[3].accessibilityLabel, "Dhuhr, current, 11:46")
        XCTAssertEqual(s.rows[4].accessibilityLabel, "Asr, next, 15:04")
        XCTAssertEqual(s.rows[6].accessibilityLabel, "Isha, 18:42")
        XCTAssertEqual(s.hero?.accessibilityLabel, "Dhuhr, current, 1 hour 11 minutes left, next Asr at 15:04")
        XCTAssertEqual(s.forbiddenSummary?.accessibilityLabel, "Next forbidden window, 17:12 to 17:27")
        XCTAssertEqual(s.statusAccessibilityLabel, "Dhuhr, current, ends in 1 hour 11 minutes")
    }

    func testInvalidEventRow() {
        var events = mockup()
        events[3] = ev(.duha, 28, nil, nil)
        let s = present(at(28, 6, 0), events: events)
        XCTAssertEqual(s.rows[2].timeText, "—")
        XCTAssertEqual(s.rows[2].accessibilityLabel, "Duha, no time today")
        XCTAssertEqual(s.rows[2].marker, .none)
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
        XCTAssertEqual(s.rows.count, 7)
        XCTAssertFalse(s.rows.contains { $0.id == .isha && $0.marker == .current })
        XCTAssertEqual(s.rows[0].marker, .next)
    }

    // MARK: Hero

    func testHeroCurrent() {
        let h = present(at(28, 13, 52, 30)).hero
        XCTAssertEqual(h?.kind, .current)
        XCTAssertEqual(h?.title, "Dhuhr")
        XCTAssertEqual(h?.countdownText, "1h 11m left")
        XCTAssertEqual(h?.progress ?? 0, (126.5 / 198), accuracy: 0.001)
        XCTAssertEqual(h?.startText, "11:46")
        XCTAssertEqual(h?.nextText, "Asr 15:04")
    }

    func testHeroForbiddenEvenWhenDisabledAndBannerNow() {
        let h = present(at(28, 11, 40)) {
            $0.styles[.istiwa] = .disabled
            $0.bannerNow = .asr
        }.hero
        XCTAssertEqual(h?.kind, .forbidden)
        XCTAssertEqual(h?.title, "Forbidden · Noon")
        XCTAssertEqual(h?.countdownText, "6m left")
        XCTAssertEqual(h?.progress ?? 0, 0.4, accuracy: 0.001)
        XCTAssertEqual(h?.startText, "11:36")
        XCTAssertEqual(h?.nextText, "Dhuhr 11:46")
        XCTAssertEqual(h?.accessibilityLabel, "Forbidden (noon), forbidden window, 6 minutes left, next Dhuhr at 11:46")
        let sunset = present(at(28, 17, 15)).hero
        XCTAssertEqual(sunset?.title, "Forbidden · Sunset")
        XCTAssertEqual(sunset?.nextText, "Maghrib 17:27")
    }

    func testHeroNextHasNoProgress() {
        let h = present(at(28, 7, 0)).hero
        XCTAssertEqual(h?.kind, .next)
        XCTAssertEqual(h?.title, "Next · Forbidden (noon)")
        XCTAssertEqual(h?.countdownText, "4h 36m")
        XCTAssertNil(h?.progress)
        XCTAssertEqual(h?.startText, "11:36")
        XCTAssertNil(h?.nextText)
        XCTAssertEqual(h?.accessibilityLabel, "Next, Forbidden (noon), in 4 hours 36 minutes, at 11:36")
    }

    func testHeroCurrentWithoutNextOmitsNext() {
        let h = present(at(28, 20, 0)).hero
        XCTAssertEqual(h?.title, "Isha")
        XCTAssertNil(h?.nextText)
        XCTAssertEqual(h?.accessibilityLabel, "Isha, current, 3 hours 59 minutes left")
    }

    func testHeroNilWithNothingCurrentOrNext() {
        let s = present(at(28, 12, 0)) { i in EventID.allCases.forEach { i.styles[$0] = .disabled } }
        XCTAssertNil(s.hero)
    }

    // MARK: Forbidden summary

    func testForbiddenSummary() {
        XCTAssertEqual(present(at(28, 13, 52, 30)).forbiddenSummary?.text, "Next forbidden 17:12–17:27")
        let none = present(at(28, 17, 30)).forbiddenSummary
        XCTAssertEqual(none?.text, "No more forbidden windows today")
        XCTAssertEqual(none?.accessibilityLabel, "No more forbidden windows today")
        XCTAssertEqual(present(at(28, 11, 40)).forbiddenSummary?.text, "Next forbidden 17:12–17:27")
        XCTAssertEqual(
            present(at(28, 13, 0)) { $0.styles[.ghurub] = .disabled }.forbiddenSummary?.text, "Next forbidden 17:12–17:27")
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
        XCTAssertNil(s.hero)
        XCTAssertNil(s.forbiddenSummary)
        XCTAssertNil(MenuPresenter.present(MenuInput(now: at(28, 12, 0), timeZone: tz, events: mockup())).emptyState)
    }

    private let notice = UpdateNotice(
        version: "1.4.0", releaseURL: URL(string: "https://github.com/masnun-siam/meqat/releases/tag/v1.4.0")!)

    func testUpdateRowWhenNoticeAndToggleOn() {
        let s = present(at(28, 12, 0)) { $0.updateNotice = notice }
        XCTAssertEqual(s.updateRow?.title, "Update available — 1.4.0")
        XCTAssertEqual(s.updateRow?.action, .openRelease(notice.releaseURL))
    }

    private func updateRow(canInstall: Bool, _ state: InstallState, schedule: Bool = true) -> MenuUpdateRow? {
        var n = notice
        n.canInstall = canInstall
        return present(at(28, 12, 0)) {
            $0.updateNotice = n
            $0.installState = state
            $0.hasScheduleForToday = schedule
        }.updateRow
    }

    func testUpdateRowInstallsWhenPossibleInIdleAndFailed() {
        for state in [InstallState.idle, .failed] {
            let row = updateRow(canInstall: true, state)
            XCTAssertEqual(row?.title, "Update available — 1.4.0", "\(state)")
            XCTAssertEqual(row?.action, .install, "\(state)")
        }
    }

    func testUpdateRowOpensReleaseWhenInstallNotPossible() {
        for state in [InstallState.idle, .failed] {
            let row = updateRow(canInstall: false, state)
            XCTAssertEqual(row?.title, "Update available — 1.4.0", "\(state)")
            XCTAssertEqual(row?.action, .openRelease(notice.releaseURL), "\(state)")
        }
    }

    func testUpdateRowWhileDownloading() {
        XCTAssertEqual(updateRow(canInstall: true, .downloading(percent: 42)), MenuUpdateRow(title: "Downloading update… 42%", action: nil))
    }

    func testUpdateRowWhileInstalling() {
        for state in [InstallState.verifying, .installing, .relaunching] {
            XCTAssertEqual(updateRow(canInstall: true, state), MenuUpdateRow(title: "Installing update…", action: nil), "\(state)")
        }
    }

    func testNoUpdateRowWhenToggleOffInAnyInstallState() {
        let states: [InstallState] = [.idle, .downloading(percent: 42), .verifying, .installing, .relaunching, .failed]
        for state in states {
            let s = present(at(28, 12, 0)) {
                $0.updateNotice = notice
                $0.checksForUpdates = false
                $0.installState = state
            }
            XCTAssertNil(s.updateRow, "\(state)")
            XCTAssertNil(present(at(28, 12, 0)) { $0.installState = state }.updateRow, "\(state)")
        }
    }

    func testEmptyStateUpdateRowMatchesNormalState() {
        let states: [InstallState] = [.idle, .downloading(percent: 42), .installing, .failed]
        for state in states {
            for canInstall in [true, false] {
                XCTAssertEqual(
                    updateRow(canInstall: canInstall, state, schedule: false), updateRow(canInstall: canInstall, state),
                    "\(state) \(canInstall)")
            }
        }
    }

    func testNoUpdateRowWithoutNotice() {
        XCTAssertNil(present(at(28, 12, 0)).updateRow)
    }

    func testNoUpdateRowWhenToggleOff() {
        let s = present(at(28, 12, 0)) {
            $0.updateNotice = notice
            $0.checksForUpdates = false
        }
        XCTAssertNil(s.updateRow)
    }

    func testUpdateRowInEmptyState() {
        let s = present(at(28, 12, 0)) {
            $0.hasScheduleForToday = false
            $0.updateNotice = notice
        }
        XCTAssertEqual(s.updateRow?.title, "Update available — 1.4.0")
    }

    func testTwelveHourFormat() {
        let s = present(at(28, 13, 52, 30)) {
            $0.timeFormat = .twelve
            $0.sync = MenuSyncInfo(lastSuccess: at(28, 15, 4))
        }
        XCTAssertEqual(s.rows[2].timeText, "6:20 AM–11:36 AM")
        XCTAssertEqual(
            present(at(28, 7, 0)) { $0.timeFormat = .twelve }.forbiddenSummary?.text, "Next forbidden 11:36 AM–11:46 AM")
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

    // MARK: Bangla

    private func bangla(_ now: Date, events: [ScheduledEvent]? = nil, _ tweak: (inout MenuInput) -> Void = { _ in }) -> MenuState {
        present(now, events: events) {
            $0.language = .bangla
            tweak(&$0)
        }
    }

    private func assertNoLatin(_ text: String?, allowing allowed: [String] = [], file: StaticString = #filePath, line: UInt = #line) {
        let stripped = allowed.reduce(text ?? "") { $0.replacingOccurrences(of: $1, with: "") }
        XCTAssertNil(stripped.range(of: "[A-Za-z0-9]", options: .regularExpression), text ?? "nil", file: file, line: line)
    }

    func testBanglaStatusTitleAndLabel() {
        let s = bangla(at(28, 13, 52, 30))
        XCTAssertEqual(s.statusTitle, "☾ যোহর শেষ হতে ১ঘ ১১মি")
        XCTAssertEqual(s.statusAccessibilityLabel, "যোহর, চলমান, শেষ হতে ১ ঘণ্টা ১১ মিনিট")
        XCTAssertEqual(bangla(at(28, 11, 40)).statusTitle, "⛔ নিষিদ্ধ সময় (দুপুর) শেষ হতে ৬মি")
        XCTAssertEqual(bangla(at(28, 11, 40)).statusAccessibilityLabel, "নিষিদ্ধ সময় (দুপুর), নিষিদ্ধ সময়, শেষ হতে ৬ মিনিট")
        XCTAssertEqual(bangla(at(28, 15, 5)) { $0.bannerNow = .asr }.statusTitle, "● আসর এখন")
        XCTAssertEqual(bangla(at(28, 15, 5)) { $0.bannerNow = .asr }.statusAccessibilityLabel, "আসর, এখন")
        let next = bangla(at(28, 16, 0)) { $0.styles[.asr] = .disabled }
        XCTAssertEqual(next.statusTitle, "☾ নিষিদ্ধ সময় (সূর্যাস্ত) ১ঘ ১২মি পরে")
        XCTAssertEqual(next.statusAccessibilityLabel, "নিষিদ্ধ সময় (সূর্যাস্ত), পরবর্তী, ১ ঘণ্টা ১২ মিনিট পরে")
    }

    func testBanglaNamesAndTimes() {
        let s = bangla(at(28, 13, 52, 30))
        XCTAssertEqual(s.rows[2].name, "চাশত")
        XCTAssertEqual(s.rows[1].timeText, "০৪:৫২")
        XCTAssertEqual(s.rows[2].timeText, "০৬:২০–১১:৩৬")
        XCTAssertEqual(bangla(at(28, 1, 0), events: [ev(.fajr, 28, (5, 12), (6, 5))]).rows[0].timeText, "০৫:১২")
    }

    func testBanglaCountdowns() {
        let asr = [ev(.asr, 28, (15, 4), (17, 0))]
        XCTAssertEqual(bangla(at(28, 13, 59), events: asr).statusTitle, "☾ আসর ১ঘ ৫মি পরে")
        XCTAssertEqual(bangla(at(28, 14, 52), events: asr).statusTitle, "☾ আসর ১২মি পরে")
        XCTAssertEqual(bangla(at(28, 15, 3, 1), events: asr).statusTitle, "☾ আসর <১মি পরে")
        XCTAssertEqual(bangla(at(28, 15, 3, 1), events: asr).statusAccessibilityLabel, "আসর, পরবর্তী, এক মিনিটের কম পরে")
        XCTAssertEqual(bangla(at(28, 14, 4), events: asr).statusAccessibilityLabel, "আসর, পরবর্তী, ১ ঘণ্টা পরে")
    }

    func testBanglaHeaderKeepsPlace() {
        XCTAssertEqual(bangla(at(28, 12, 0)) { $0.place = "Dhaka" }.header, "বুধ ২৮ অক্টো · Dhaka")
    }

    func testBanglaHeroSummaryRowsAndFooter() {
        let s = bangla(at(28, 13, 52, 30)) { $0.styles = [:] }
        XCTAssertEqual(s.hero?.countdownText, "১ঘ ১১মি বাকি")
        XCTAssertEqual(s.hero?.nextText, "আসর ১৫:০৪")
        XCTAssertEqual(s.hero?.accessibilityLabel, "যোহর, চলমান, ১ ঘণ্টা ১১ মিনিট বাকি, পরবর্তী আসর ১৫:০৪-এ")
        XCTAssertEqual(
            s.forbiddenSummary, MenuForbiddenSummary(text: "পরবর্তী নিষিদ্ধ সময় ১৭:১২–১৭:২৭", accessibilityLabel: "পরবর্তী নিষিদ্ধ সময়, ১৭:১২ থেকে ১৭:২৭"))
        XCTAssertEqual(s.rows[0].accessibilityLabel, "তাহাজ্জুদ, শেষ, ০১:০০")
        XCTAssertEqual(s.rows[2].accessibilityLabel, "চাশত, শেষ, ০৬:২০ থেকে ১১:৩৬")
        XCTAssertEqual(s.rows[4].accessibilityLabel, "আসর, পরবর্তী, ১৫:০৪")

        let forbidden = bangla(at(28, 11, 40)).hero
        XCTAssertEqual(forbidden?.title, "নিষিদ্ধ · দুপুর")
        XCTAssertEqual(forbidden?.accessibilityLabel, "নিষিদ্ধ সময় (দুপুর), নিষিদ্ধ সময়, ৬ মিনিট বাকি, পরবর্তী যোহর ১১:৪৬-এ")
        let next = bangla(at(28, 7, 0)).hero
        XCTAssertEqual(next?.title, "পরবর্তী · নিষিদ্ধ সময় (দুপুর)")
        XCTAssertEqual(next?.accessibilityLabel, "পরবর্তী, নিষিদ্ধ সময় (দুপুর), ৪ ঘণ্টা ৩৬ মিনিট পরে, ১১:৩৬-এ")
        XCTAssertEqual(bangla(at(28, 17, 30)).forbiddenSummary?.text, "আজ আর কোনো নিষিদ্ধ সময় নেই")

        let prev = bangla(at(29, 12, 0), events: [ev(.tahajjud, 29, (23, 30), (4, 50), prev: true, fromDay: 28)])
        XCTAssertEqual(prev.rows[0].timeText, "২৩:৩০ (আগের রাত)")
        let invalid = bangla(at(28, 6, 0), events: [ev(.duha, 28, nil, nil)])
        XCTAssertEqual(invalid.rows[0].accessibilityLabel, "চাশত, আজ কোনো সময় নেই")

        func footer(_ sync: MenuSyncInfo, couldnt: Bool = false) -> String {
            bangla(at(28, 12, 0)) {
                $0.sync = sync
                $0.showsCouldntRefresh = couldnt
            }.footerStatus
        }
        XCTAssertEqual(footer(MenuSyncInfo(lastSuccess: at(28, 9, 5))), "সিঙ্ক হয়েছে ০৯:০৫")
        XCTAssertEqual(footer(MenuSyncInfo(lastSuccess: at(27, 9, 5))), "সিঙ্ক হয়েছে ২৭ অক্টো ০৯:০৫")
        XCTAssertEqual(footer(MenuSyncInfo(lastSuccess: at(27, 9, 5), offlineSince: at(28, 8, 0))), "অফলাইন — ২৭ অক্টো-এর ক্যাশ ব্যবহার হচ্ছে")
        XCTAssertEqual(footer(MenuSyncInfo(), couldnt: true), "রিফ্রেশ করা যায়নি")
        XCTAssertEqual(footer(MenuSyncInfo(isFetching: true)), "সিঙ্ক হচ্ছে…")
    }

    func testEmptyMessages() {
        func message(_ language: Language, _ loc: MenuLocationInfo, failure: MenuFailure? = nil) -> String? {
            present(at(28, 12, 0)) {
                $0.language = language
                $0.hasScheduleForToday = false
                $0.location = loc
                $0.sync = MenuSyncInfo(lastFailure: failure)
            }.emptyMessage
        }
        XCTAssertEqual(message(.english, .awaitingPermission), "Waiting for location permission…")
        XCTAssertEqual(message(.english, .awaitingFix), "Fetching times…")
        XCTAssertEqual(message(.english, .missing, failure: .other), "Set your location")
        XCTAssertEqual(message(.english, .available, failure: .cityNotFound), "City not found — check Location settings")
        XCTAssertEqual(message(.english, .available, failure: .other), "No schedule — connect to the internet")
        XCTAssertEqual(message(.bangla, .awaitingPermission), "লোকেশনের অনুমতির অপেক্ষায়…")
        XCTAssertEqual(message(.bangla, .awaitingFix), "সময় আনা হচ্ছে…")
        XCTAssertEqual(message(.bangla, .missing, failure: .other), "আপনার লোকেশন সেট করুন")
        XCTAssertEqual(message(.bangla, .available, failure: .cityNotFound), "শহর পাওয়া যায়নি — লোকেশন সেটিংস দেখুন")
        XCTAssertEqual(message(.bangla, .available, failure: .other), "সময়সূচি নেই — ইন্টারনেটে সংযোগ দিন")
        XCTAssertNil(present(at(28, 12, 0)).emptyMessage)
    }

    func testBanglaUpdateRowKeepsLatinVersion() {
        func row(_ state: InstallState) -> String? {
            bangla(at(28, 12, 0)) {
                $0.updateNotice = UpdateNotice(version: "1.8.0", releaseURL: notice.releaseURL)
                $0.installState = state
            }.updateRow?.title
        }
        XCTAssertEqual(row(.idle), "আপডেট আছে — 1.8.0")
        XCTAssertEqual(row(.downloading(percent: 42)), "আপডেট ডাউনলোড হচ্ছে… ৪২%")
        XCTAssertEqual(row(.installing), "আপডেট ইনস্টল হচ্ছে…")
    }

    func testBanglaTwelveHour() {
        let s = bangla(at(28, 13, 52, 30)) {
            $0.timeFormat = .twelve
            $0.sync = MenuSyncInfo(lastSuccess: at(28, 15, 4))
        }
        XCTAssertEqual(s.rows[2].timeText, "৬:২০ AM–১১:৩৬ AM")
        XCTAssertEqual(s.footerStatus, "সিঙ্ক হয়েছে ৩:০৪ PM")
    }

    func testBanglaTwentyFourHourHasNoLatin() {
        for now in [at(28, 13, 52, 30), at(28, 11, 40), at(28, 7, 0), at(28, 17, 30)] {
            let s = bangla(now) {
                $0.place = "Dhaka"
                $0.styles = [:]
            }
            assertNoLatin(s.statusTitle)
            assertNoLatin(s.statusAccessibilityLabel)
            assertNoLatin(s.header, allowing: ["Dhaka"])
            assertNoLatin(s.hero?.title)
            assertNoLatin(s.hero?.countdownText)
            assertNoLatin(s.hero?.startText)
            assertNoLatin(s.hero?.nextText)
            assertNoLatin(s.hero?.accessibilityLabel)
            assertNoLatin(s.forbiddenSummary?.text)
            assertNoLatin(s.forbiddenSummary?.accessibilityLabel)
            s.rows.forEach {
                assertNoLatin($0.name)
                assertNoLatin($0.timeText)
                assertNoLatin($0.accessibilityLabel)
            }
        }
    }
}
