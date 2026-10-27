import CoreLocation
import XCTest
@testable import MeqatCore

final class SyncPolicyTests: XCTestCase {
    private let today = LocalDate(year: 2026, month: 10, day: 28)
    private let dhaka = Coordinates(latitude: 23.8103, longitude: 90.4125)
    private let utc = TimeZone(identifier: "UTC")!

    private func day(_ date: LocalDate) -> DayTimings {
        let t = date.startOfDay(in: utc)
        return DayTimings(date: date, fajr: t, sunrise: t, dhuhr: t, asr: t, sunset: t, maghrib: t, isha: t, midnight: t, lastthird: t)
    }

    private func params(_ location: FetchLocation? = nil, method: Int? = 2, school: Int = 0, tz: String = "Asia/Dhaka") -> FetchParameters {
        FetchParameters(location: location ?? .coordinates(dhaka), method: method, school: school, timeZoneId: tz)
    }

    private func cache(_ p: FetchParameters, through: Int = 30) -> TimingsCache {
        let dates = (-1...through).map { today.adding(days: $0) }
        return TimingsCache(parameters: p, fetchedAt: Date(timeIntervalSince1970: 0), days: Dictionary(uniqueKeysWithValues: dates.map { ($0, day($0)) }))
    }

    private func needs(_ cache: TimingsCache?, _ current: FetchParameters) -> Bool {
        SyncPolicy.needsFetch(cache: cache, current: current, today: today)
    }

    func testMatchingFullCacheNeedsNoFetch() {
        XCTAssertFalse(needs(cache(params()), params()))
    }

    func testNoCacheOrShortCoverageFetches() {
        XCTAssertTrue(needs(nil, params()))
        XCTAssertTrue(needs(cache(params(), through: 29), params()))
    }

    func testMissingYesterdayFetches() {
        var c = cache(params())
        c.days[today.adding(days: -1)] = nil
        XCTAssertTrue(needs(c, params()))
    }

    func testMovedCoordinates() {
        // 1 degree of latitude is ~111.2 km, so 0.036 deg is ~4 km and 0.054 deg is ~6 km.
        let base = CLLocation(latitude: dhaka.latitude, longitude: dhaka.longitude)
        let near = Coordinates(latitude: dhaka.latitude + 0.036, longitude: dhaka.longitude)
        let far = Coordinates(latitude: dhaka.latitude + 0.054, longitude: dhaka.longitude)
        XCTAssertEqual(base.distance(from: CLLocation(latitude: near.latitude, longitude: near.longitude)), 4_000, accuracy: 100)
        XCTAssertEqual(base.distance(from: CLLocation(latitude: far.latitude, longitude: far.longitude)), 6_000, accuracy: 100)
        XCTAssertFalse(needs(cache(params()), params(.coordinates(near))))
        XCTAssertTrue(needs(cache(params()), params(.coordinates(far))))
    }

    func testManualCityChanges() {
        let base = FetchLocation.city(city: "Dhaka", country: "Bangladesh", state: nil)
        let c = cache(params(base))
        XCTAssertFalse(needs(c, params(base)))
        XCTAssertTrue(needs(c, params(.city(city: "Sylhet", country: "Bangladesh", state: nil))))
        XCTAssertTrue(needs(c, params(.city(city: "Dhaka", country: "India", state: nil))))
        XCTAssertTrue(needs(c, params(.city(city: "Dhaka", country: "Bangladesh", state: "Dhaka Division"))))
        XCTAssertTrue(needs(cache(params(.city(city: "Dhaka", country: "Bangladesh", state: "Dhaka Division"))), params(base)))
    }

    func testModeChangeAndStrippedCache() {
        let city = FetchLocation.city(city: "Dhaka", country: "Bangladesh", state: nil)
        XCTAssertTrue(needs(cache(params()), params(city)))
        XCTAssertTrue(needs(cache(params(city)), params()))
        var stripped = cache(params())
        stripped.parameters.location = nil
        XCTAssertTrue(needs(stripped, params()))
    }

    func testMethodSchoolAndTimeZoneChanges() {
        let c = cache(params())
        XCTAssertTrue(needs(c, params(method: 3)))
        XCTAssertTrue(needs(c, params(method: nil)))
        XCTAssertTrue(needs(cache(params(method: nil)), params(method: 2)))
        XCTAssertTrue(needs(c, params(school: 1)))
        XCTAssertTrue(needs(c, params(tz: "Asia/Karachi")))
    }

    func testMonths() {
        func ym(_ y: Int, _ m: Int) -> YearMonth { YearMonth(year: y, month: m) }
        XCTAssertEqual(SyncPolicy.months(today: LocalDate(year: 2026, month: 1, day: 15)), [ym(2026, 1), ym(2026, 2)])
        XCTAssertEqual(SyncPolicy.months(today: LocalDate(year: 2026, month: 1, day: 30)), [ym(2026, 1), ym(2026, 2), ym(2026, 3)])
        XCTAssertEqual(SyncPolicy.months(today: LocalDate(year: 2026, month: 1, day: 1)), [ym(2025, 12), ym(2026, 1)])
        XCTAssertEqual(SyncPolicy.months(today: LocalDate(year: 2026, month: 2, day: 1)), [ym(2026, 1), ym(2026, 2), ym(2026, 3)])
        XCTAssertEqual(SyncPolicy.months(today: LocalDate(year: 2026, month: 12, day: 31)), [ym(2026, 12), ym(2027, 1)])
        XCTAssertEqual(SyncPolicy.months(today: LocalDate(year: 2026, month: 3, day: 1)), [ym(2026, 2), ym(2026, 3)])
    }

    func testCurrentParameters() {
        let tz = TimeZone(identifier: "Asia/Dhaka")!
        let general = GeneralSettings(method: 2, school: .hanafi)
        XCTAssertNil(FetchParameters.current(general: general, location: LocationSettings(), coordinates: nil, timeZone: tz))
        XCTAssertEqual(
            FetchParameters.current(general: general, location: LocationSettings(), coordinates: dhaka, timeZone: tz),
            FetchParameters(location: .coordinates(dhaka), method: 2, school: 1, timeZoneId: "Asia/Dhaka"))
        let noCountry = LocationSettings(mode: .manual, manualCity: "Dhaka", manualCountry: "")
        XCTAssertNil(FetchParameters.current(general: general, location: noCountry, coordinates: dhaka, timeZone: tz))
        let manual = LocationSettings(mode: .manual, manualCity: "Dhaka", manualCountry: "Bangladesh", manualState: "")
        XCTAssertEqual(
            FetchParameters.current(general: general, location: manual, coordinates: nil, timeZone: tz)?.location,
            .city(city: "Dhaka", country: "Bangladesh", state: nil))
    }
}
