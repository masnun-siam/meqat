import XCTest

@testable import MeqatCore

final class EventEngineTests: XCTestCase {
    private let dhaka = TimeZone(identifier: "Asia/Dhaka")!
    private let newYork = TimeZone(identifier: "America/New_York")!

    private func cache(_ name: String) throws -> TimingsCache {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TimingsCache.self, from: Fixture.data("engine/\(name).json"))
    }

    private func events(_ cache: TimingsCache, _ date: LocalDate, tz: TimeZone? = nil, _ settings: AppSettings = AppSettings()) throws
        -> [EventID: ScheduledEvent]
    {
        let list = try XCTUnwrap(EventEngine.events(for: date, cache: cache, settings: settings, timeZone: tz ?? dhaka))
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }

    private func settings(_ id: EventID, at time: ClockTime, general: GeneralSettings = .init()) -> AppSettings {
        var s = AppSettings(general: general)
        s.events[id]!.timeSource = .fixed
        s.events[id]!.staticTime = time
        return s
    }

    private func at(_ date: LocalDate, _ h: Int, _ m: Int, tz: TimeZone? = nil) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz ?? dhaka
        return calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: h, minute: m))!
    }

    private let oct28 = LocalDate(year: 2026, month: 10, day: 28)
    private let oct29 = LocalDate(year: 2026, month: 10, day: 29)
    private let oct30 = LocalDate(year: 2026, month: 10, day: 30)

    func testFridayHasTenEventsInOrderWithJumah() throws {
        let c = try cache("dhaka-2026-10-28-30")
        let list = try XCTUnwrap(EventEngine.events(for: oct30, cache: c, settings: AppSettings(), timeZone: dhaka))
        XCTAssertEqual(list.map(\.id), [.tahajjud, .fajr, .shuruq, .duha, .istiwa, .jumah, .asr, .ghurub, .maghrib, .isha])
        let day = c.day(oct30)!
        let e = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        XCTAssertEqual(e[.jumah]?.interval, DateInterval(start: day.dhuhr, end: day.asr))
        XCTAssertEqual(e[.istiwa]?.interval, DateInterval(start: day.dhuhr - 600, end: day.dhuhr))
        XCTAssertEqual(e[.duha]?.interval, DateInterval(start: day.sunrise + 900, end: day.dhuhr - 600))
        XCTAssertTrue(list.allSatisfy { $0.interval != nil && $0.interval == $0.calculatedInterval && !$0.startsPreviousNight })
    }

    func testThursdayHasDhuhrNotJumah() throws {
        let list = try XCTUnwrap(
            EventEngine.events(for: oct29, cache: cache("dhaka-2026-10-28-30"), settings: AppSettings(), timeZone: dhaka))
        XCTAssertEqual(list.count, 10)
        XCTAssertTrue(list.contains { $0.id == .dhuhr })
        XCTAssertFalse(list.contains { $0.id == .jumah })
    }

    func testMissingDayReturnsNil() throws {
        XCTAssertNil(
            EventEngine.events(
                for: LocalDate(year: 2026, month: 11, day: 5), cache: try cache("dhaka-2026-10-28-30"), settings: AppSettings(),
                timeZone: dhaka))
    }

    func testIshaEndsAfterMidnightOnNextDate() throws {
        let e = try events(cache("isha-after-midnight"), oct30)
        XCTAssertEqual(e[.isha]?.interval?.end, at(LocalDate(year: 2026, month: 10, day: 31), 0, 14))
    }

    func testTahajjudStartsAtPreviousLastthird() throws {
        let e = try events(cache("lastthird-27-28-oct"), oct28)
        let tahajjud = try XCTUnwrap(e[.tahajjud]?.interval)
        XCTAssertEqual(tahajjud.start, at(oct28, 2, 50))
        XCTAssertEqual(tahajjud.end, try cache("lastthird-27-28-oct").day(oct28)!.fajr)
    }

    func testMissingPreviousDayInvalidatesTahajjud() throws {
        let e = try events(cache("dhaka-2026-10-28-30"), oct28)
        XCTAssertNil(e[.tahajjud]?.interval)
        XCTAssertNil(e[.tahajjud]?.calculatedInterval)
        XCTAssertNotNil(e[.fajr]?.interval)
    }

    func testStaticIstiwaMovesItsEndAndDuhaEnd() throws {
        let c = try cache("dhaka-2026-10-28-30")
        let e = try events(c, oct29, settings(.istiwa, at: ClockTime(hour: 11, minute: 30)))
        XCTAssertEqual(e[.istiwa]?.interval, DateInterval(start: at(oct29, 11, 30), end: at(oct29, 11, 40)))
        XCTAssertEqual(e[.duha]?.interval?.end, at(oct29, 11, 30))
        XCTAssertEqual(e[.istiwa]?.calculatedInterval?.end, c.day(oct29)!.dhuhr)
    }

    func testStaticShuruqAndGhurubKeepTheirDuration() throws {
        let c = try cache("dhaka-2026-10-28-30")
        let shuruq = try events(c, oct29, settings(.shuruq, at: ClockTime(hour: 6, minute: 10)))
        XCTAssertEqual(shuruq[.shuruq]?.interval, DateInterval(start: at(oct29, 6, 10), end: at(oct29, 6, 25)))
        XCTAssertEqual(shuruq[.duha]?.interval?.start, at(oct29, 6, 25))
        let ghurub = try events(c, oct29, settings(.ghurub, at: ClockTime(hour: 17, minute: 0)))
        XCTAssertEqual(ghurub[.ghurub]?.interval, DateInterval(start: at(oct29, 17, 0), end: at(oct29, 17, 15)))
    }

    func testStaticDhuhrKeepsAsrEndAndInvalidAfterAsr() throws {
        let c = try cache("dhaka-2026-10-28-30")
        let late = try events(c, oct29, settings(.dhuhr, at: ClockTime(hour: 12, minute: 30)))
        XCTAssertEqual(late[.dhuhr]?.interval, DateInterval(start: at(oct29, 12, 30), end: c.day(oct29)!.asr))
        let afterAsr = try events(c, oct29, settings(.dhuhr, at: ClockTime(hour: 16, minute: 0)))
        XCTAssertNil(afterAsr[.dhuhr]?.interval)
        XCTAssertNotNil(afterAsr[.dhuhr]?.calculatedInterval)
    }

    func testStaticJumahAppliesOnlyOnFriday() throws {
        let c = try cache("dhaka-2026-10-28-30")
        let s = settings(.jumah, at: ClockTime(hour: 13, minute: 15))
        XCTAssertEqual(try events(c, oct30, s)[.jumah]?.interval?.start, at(oct30, 13, 15))
        XCTAssertEqual(try events(c, oct29, s)[.dhuhr]?.interval?.start, c.day(oct29)!.dhuhr)
    }

    func testStaticTahajjud() throws {
        let c = try cache("dhaka-2026-10-28-30")
        let fajr = c.day(oct29)!.fajr
        let isha = Calendar(identifier: .gregorian).dateComponents(in: dhaka, from: c.day(oct28)!.isha)
        let ishaTime = ClockTime(hour: isha.hour!, minute: isha.minute!)

        let morning = try events(c, oct29, settings(.tahajjud, at: ClockTime(hour: 4, minute: 0)))[.tahajjud]!
        XCTAssertEqual(morning.interval, DateInterval(start: at(oct29, 4, 0), end: fajr))
        XCTAssertFalse(morning.startsPreviousNight)

        let late = try events(c, oct29, settings(.tahajjud, at: ClockTime(hour: 23, minute: 30)))[.tahajjud]!
        XCTAssertEqual(late.interval?.start, at(oct28, 23, 30))
        XCTAssertTrue(late.startsPreviousNight)

        let exact = try events(c, oct29, settings(.tahajjud, at: ishaTime))[.tahajjud]!
        XCTAssertTrue(exact.startsPreviousNight)
        XCTAssertEqual(exact.interval?.start, at(oct28, ishaTime.hour, ishaTime.minute))

        let beforeIsha = try events(c, oct29, settings(.tahajjud, at: ClockTime(hour: ishaTime.hour, minute: ishaTime.minute - 1)))[
            .tahajjud]!
        XCTAssertFalse(beforeIsha.startsPreviousNight)

        let noon = try events(c, oct29, settings(.tahajjud, at: ClockTime(hour: 12, minute: 0)))[.tahajjud]!
        XCTAssertNil(noon.interval)
        XCTAssertNotNil(noon.calculatedInterval)

        let afterFajr = try events(c, oct29, settings(.tahajjud, at: ClockTime(hour: 5, minute: 55)))[.tahajjud]!
        XCTAssertNil(afterFajr.interval)
    }

    func testWindowDurationsChangeProhibitedWindows() throws {
        let c = try cache("dhaka-2026-10-28-30")
        let day = c.day(oct29)!
        var general = GeneralSettings(shuruqMinutes: 5, istiwaMinutes: 30, ghurubMinutes: 20)
        var e = try events(c, oct29, AppSettings(general: general))
        XCTAssertEqual(e[.shuruq]?.interval, DateInterval(start: day.sunrise, duration: 300))
        XCTAssertEqual(e[.istiwa]?.interval, DateInterval(start: day.dhuhr - 1800, end: day.dhuhr))
        XCTAssertEqual(e[.ghurub]?.interval, DateInterval(start: day.sunset - 1200, end: day.sunset))
        general.shuruqMinutes = 30
        e = try events(c, oct29, AppSettings(general: general))
        XCTAssertEqual(e[.shuruq]?.interval?.duration, 1800)
    }

    func testFixedWithoutTimeIsCalculated() throws {
        var s = AppSettings()
        s.events[.fajr]!.timeSource = .fixed
        let c = try cache("dhaka-2026-10-28-30")
        let e = try events(c, oct29, s)
        XCTAssertEqual(e[.fajr]?.interval?.start, c.day(oct29)!.fajr)
    }

    func testDSTDayUsesNewOffsetAndSkippedMinuteMovesForward() throws {
        let mar8 = LocalDate(year: 2026, month: 3, day: 8)
        let c = try cache("new-york-2026-03-08")
        let e = try events(c, mar8, tz: newYork)
        XCTAssertEqual(e[.fajr]?.interval?.start, at(mar8, 6, 4, tz: newYork))
        XCTAssertEqual(
            e[.fajr]?.interval?.start.timeIntervalSince1970,
            ISO8601DateFormatter().date(from: "2026-03-08T06:04:00-04:00")?.timeIntervalSince1970)

        let skipped = try events(c, mar8, tz: newYork, settings(.fajr, at: ClockTime(hour: 2, minute: 30)))
        XCTAssertEqual(skipped[.fajr]?.interval?.start, at(mar8, 3, 0, tz: newYork))
    }

    func testHighLatitudeNeverProducesNonPositiveInterval() throws {
        let c = try cache("high-latitude")
        for date in c.days.keys.sorted() {
            let list = try XCTUnwrap(
                EventEngine.events(for: date, cache: c, settings: AppSettings(), timeZone: TimeZone(identifier: "Europe/Oslo")!))
            XCTAssertEqual(list.count, 10)
            for event in list { XCTAssertTrue((event.interval?.duration ?? 1) > 0, "\(event.id) on \(date)") }
        }
        let edited = try events(c, LocalDate(year: 2026, month: 6, day: 22), tz: TimeZone(identifier: "Europe/Oslo")!)
        XCTAssertNil(edited[.duha]?.interval)
    }
}
