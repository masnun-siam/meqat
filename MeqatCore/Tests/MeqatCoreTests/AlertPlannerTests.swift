import XCTest

@testable import MeqatCore

final class AlertPlannerTests: XCTestCase {
    private let tz = TimeZone(identifier: "Asia/Dhaka")!
    private let oct28 = LocalDate(year: 2026, month: 10, day: 28)

    private func at(_ day: Int, _ h: Int, _ m: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }

    private func event(_ id: EventID, from: Date, to: Date, date: LocalDate? = nil, valid: Bool = true) -> ScheduledEvent {
        let i = valid ? DateInterval(start: from, end: to) : nil
        return ScheduledEvent(id: id, date: date ?? oct28, interval: i, calculatedInterval: i)
    }

    private func settings(
        _ id: EventID, start: StartAlert = StartAlert(style: .disabled),
        end: LeadAlert = LeadAlert(style: .disabled, leadMinutes: 15),
        pre: LeadAlert = LeadAlert(style: .disabled, leadMinutes: 20)
    ) -> AppSettings {
        var s = AppSettings()
        s.events[id] = EventSettings(startAlert: start, endAlert: end, preWarning: pre)
        return s
    }

    private func plan(_ events: [ScheduledEvent], _ s: AppSettings, now: Date? = nil) -> [PlannedAlert] {
        AlertPlanner.plan(events: events, settings: s, now: now ?? at(28, 0, 0), timeZone: tz)
    }

    /// Plans with `tweak` applied to every event's settings.
    private func plan(_ events: [ScheduledEvent], _ s: AppSettings, _ tweak: (inout EventSettings) -> Void) -> [PlannedAlert] {
        var t = s
        for id in t.events.keys { tweak(&t.events[id]!) }
        return plan(events, t)
    }

    func testDhuhrStartOffsetAndEndLead() {
        let s = settings(.dhuhr, start: StartAlert(offsetMinutes: 5), end: LeadAlert(style: .banner, leadMinutes: 15))
        let p = plan([event(.dhuhr, from: at(28, 11, 46), to: at(28, 15, 4))], s)
        XCTAssertEqual(p.map(\.fireDate), [at(28, 11, 51), at(28, 14, 49)])
        XCTAssertEqual(p.map(\.id), ["2026-10-28.dhuhr.start", "2026-10-28.dhuhr.end"])
    }

    func testStaticDhuhrMovesStartOnly() {
        let s = settings(.dhuhr, start: StartAlert(offsetMinutes: 5), end: LeadAlert(style: .banner, leadMinutes: 15))
        let p = plan([event(.dhuhr, from: at(28, 12, 30), to: at(28, 15, 4))], s)
        XCTAssertEqual(p.map(\.fireDate), [at(28, 12, 35), at(28, 14, 49)])
    }

    func testIshaEndAlertBeforeMidnight() {
        let s = settings(.isha, start: StartAlert(style: .disabled), end: LeadAlert(style: .banner, leadMinutes: 15))
        let p = plan([event(.isha, from: at(28, 19, 0), to: at(29, 0, 14))], s)
        XCTAssertEqual(p.map(\.fireDate), [at(28, 23, 59)])
        XCTAssertEqual(p[0].id, "2026-10-28.isha.end")
    }

    func testDisabledAndInvalidHaveNoAlerts() {
        let on = StartAlert()
        let lead = LeadAlert(style: .banner, leadMinutes: 15)
        let disabled = settings(.asr)
        XCTAssertTrue(plan([event(.asr, from: at(28, 15, 4), to: at(28, 17, 0))], disabled).isEmpty)
        let enabled = settings(.asr, start: on, end: lead, pre: lead)
        XCTAssertTrue(plan([event(.asr, from: at(28, 15, 4), to: at(28, 17, 0), valid: false)], enabled).isEmpty)
    }

    func testEachAlertFiresInItsOwnStyle() {
        let s = settings(
            .asr, start: StartAlert(style: .fullScreen), end: LeadAlert(style: .banner, leadMinutes: 15),
            pre: LeadAlert(style: .fullScreen, leadMinutes: 20))
        let p = plan([event(.asr, from: at(28, 15, 4), to: at(28, 17, 0))], s)
        XCTAssertEqual(p.map(\.kind), [.preWarning, .start, .end])
        XCTAssertEqual(p.map(\.style), [.fullScreen, .fullScreen, .banner])
    }

    func testFullScreenPreWarningAlone() {
        let s = settings(.asr, pre: LeadAlert(style: .fullScreen, leadMinutes: 20))
        let p = plan([event(.asr, from: at(28, 15, 4), to: at(28, 17, 0))], s)
        XCTAssertEqual(p.map(\.kind), [.preWarning])
        XCTAssertEqual(p.map(\.style), [.fullScreen])
        XCTAssertEqual(p.map(\.fireDate), [at(28, 14, 44)])
        XCTAssertEqual(p.map(\.title), ["Asr in 20 min"])
    }

    func testEachOffAlertIsNotPlanned() {
        let asr = [event(.asr, from: at(28, 15, 4), to: at(28, 17, 0))]
        let on = StartAlert(style: .banner)
        let lead = LeadAlert(style: .banner, leadMinutes: 15)
        let off = LeadAlert(style: .disabled, leadMinutes: 15)
        let kinds = { (s: AppSettings) in self.plan(asr, s).map(\.kind) }
        XCTAssertEqual(kinds(settings(.asr, start: StartAlert(style: .disabled), end: lead, pre: lead)), [.preWarning, .end])
        XCTAssertEqual(kinds(settings(.asr, start: on, end: off, pre: lead)), [.preWarning, .start])
        XCTAssertEqual(kinds(settings(.asr, start: on, end: lead, pre: off)), [.start, .end])
    }

    func testAllOffYieldsNothingAndOneOnShowsOnlyIt() {
        let dhuhr = [event(.dhuhr, from: at(28, 11, 46), to: at(28, 15, 4))]
        XCTAssertTrue(plan(dhuhr, settings(.dhuhr)).isEmpty)
        let endOnly = settings(.dhuhr, end: LeadAlert(style: .banner, leadMinutes: 15))
        XCTAssertEqual(plan(dhuhr, endOnly).map(\.id), ["2026-10-28.dhuhr.end"])
    }

    func testTitlesForPrayerAndProhibitedWindow() {
        let s1 = settings(
            .asr, start: StartAlert(), end: LeadAlert(style: .banner, leadMinutes: 15), pre: LeadAlert(style: .banner, leadMinutes: 20))
        XCTAssertEqual(
            plan([event(.asr, from: at(28, 15, 4), to: at(28, 17, 0))], s1).map(\.title),
            ["Asr in 20 min", "Asr · 15:04", "Asr ends in 15 min"])
        let s2 = settings(
            .istiwa, start: StartAlert(), end: LeadAlert(style: .banner, leadMinutes: 15), pre: LeadAlert(style: .banner, leadMinutes: 20))
        // end alert (11:31) precedes start (11:36)
        XCTAssertEqual(
            plan([event(.istiwa, from: at(28, 11, 36), to: at(28, 11, 46))], s2).map(\.title),
            ["⛔ Forbidden (noon) in 20 min", "Forbidden (noon) ends in 15 min", "⛔ Forbidden (noon) · avoid praying until 11:46"])
    }

    func testOverlayLineIsTitleExceptForStart() {
        let s = settings(
            .asr, start: StartAlert(style: .fullScreen), end: LeadAlert(style: .banner, leadMinutes: 15),
            pre: LeadAlert(style: .banner, leadMinutes: 20))
        let p = plan([event(.asr, from: at(28, 15, 4), to: at(28, 17, 0))], s)
        XCTAssertEqual(p.map(\.kind), [.preWarning, .start, .end])
        XCTAssertEqual(p.map(\.overlayLine), ["Asr in 20 min", nil, "Asr ends in 15 min"])
    }

    func testOverlayLineNamesProhibitedWindowsByDisplayName() {
        let pre = LeadAlert(style: .banner, leadMinutes: 15)
        let windows: [(EventID, String)] = [
            (.shuruq, "⛔ Forbidden (sunrise) in 15 min"), (.istiwa, "⛔ Forbidden (noon) in 15 min"),
            (.ghurub, "⛔ Forbidden (sunset) in 15 min"),
        ]
        for (id, expected) in windows {
            let p = plan([event(id, from: at(28, 11, 36), to: at(28, 11, 46))], settings(id, pre: pre))
            XCTAssertEqual(p.map(\.overlayLine), [expected])
            let line = p.first?.overlayLine ?? ""
            for arabic in ["Shuruq", "Istiwa", "Ghurub"] { XCTAssertFalse(line.contains(arabic)) }
        }
    }

    func testTwelveHourTitles() {
        var s = settings(.istiwa, start: StartAlert())
        s.general.timeFormat = .twelve
        XCTAssertEqual(
            plan([event(.istiwa, from: at(28, 11, 36), to: at(28, 11, 46))], s).map(\.title),
            ["⛔ Forbidden (noon) · avoid praying until 11:46 AM"])
        var d = settings(.dhuhr, start: StartAlert())
        d.general.timeFormat = .twelve
        XCTAssertEqual(plan([event(.dhuhr, from: at(28, 11, 46), to: at(28, 15, 4))], d).map(\.title), ["Dhuhr · 11:46 AM"])
    }

    func testPastAndBeyond48hSkipped() {
        let s = settings(.asr, start: StartAlert())
        let events = [
            event(.asr, from: at(28, 15, 4), to: at(28, 17, 0)),
            event(.asr, from: at(28, 15, 4) + 3 * 86400, to: at(28, 17, 0) + 3 * 86400, date: LocalDate(year: 2026, month: 10, day: 31)),
        ]
        XCTAssertTrue(plan(events, s, now: at(28, 15, 4)).isEmpty)  // at now: skipped
        XCTAssertEqual(plan(events, s, now: at(28, 15, 3)).count, 1)
        XCTAssertEqual(plan(events, s, now: at(29, 15, 4)).map(\.id), ["2026-10-31.asr.start"])  // exactly 48h: kept
        XCTAssertTrue(plan(events, s, now: at(29, 15, 3)).isEmpty)  // 48h + 1 min: dropped
    }

    func testBannerCapKeepsSoonest60AndFullScreenUncapped() {
        let on = LeadAlert(style: .banner, leadMinutes: 15)
        var s = AppSettings()
        for id in EventID.allCases { s.events[id] = EventSettings(startAlert: StartAlert(), endAlert: on, preWarning: on) }
        var events: [ScheduledEvent] = []
        for d in 0..<3 {
            for (n, id) in EventID.allCases.enumerated() {
                let from = at(28, 1, 0) + TimeInterval(d * 86400 + n * 3600)
                events.append(event(id, from: from, to: from + 1800, date: LocalDate(year: 2026, month: 10, day: 28 + d)))
            }
        }
        let p = plan(events, s)
        XCTAssertEqual(p.count, 60)
        XCTAssertEqual(Set(p.map(\.id)).count, 60)

        for id in EventID.allCases {
            s.events[id]!.startAlert.style = .fullScreen
            s.events[id]!.endAlert.style = .fullScreen
        }
        let full = plan(events, s)
        XCTAssertGreaterThan(full.count, 60)
        let preOnly = plan(events, s) {
            $0.startAlert.style = .disabled; $0.endAlert.style = .disabled
        }
        let fullOnly = plan(events, s) { $0.preWarning.style = .disabled }
        XCTAssertLessThanOrEqual(preOnly.count, 60)
        XCTAssertEqual(full.filter { $0.style == .banner }.map(\.id), preOnly.map(\.id))
        XCTAssertEqual(full.filter { $0.style == .fullScreen }.map(\.id), fullOnly.map(\.id))
    }

    func testBoundsOffsetsAndLeads() {
        let from = at(28, 12, 0)
        let to = at(28, 14, 0)
        var s = settings(
            .asr, start: StartAlert(offsetMinutes: -60), end: LeadAlert(style: .banner, leadMinutes: 120),
            pre: LeadAlert(style: .banner, leadMinutes: 1))
        XCTAssertEqual(plan([event(.asr, from: from, to: to)], s).map(\.fireDate), [at(28, 11, 0), at(28, 11, 59), at(28, 12, 0)])
        s = settings(
            .asr, start: StartAlert(offsetMinutes: 60), end: LeadAlert(style: .banner, leadMinutes: 1),
            pre: LeadAlert(style: .banner, leadMinutes: 120))
        XCTAssertEqual(plan([event(.asr, from: from, to: to)], s).map(\.fireDate), [at(28, 10, 0), at(28, 13, 0), at(28, 13, 59)])
    }

    func testSameInstantKeptWithDistinctIds() {
        let s = settings(.asr, start: StartAlert(), end: LeadAlert(style: .banner, leadMinutes: 1))
        let p = plan([event(.asr, from: at(28, 15, 0), to: at(28, 15, 1))], s)
        XCTAssertEqual(p.count, 2)
        XCTAssertEqual(p[0].fireDate, p[1].fireDate)
        XCTAssertNotEqual(p[0].id, p[1].id)
    }
}
