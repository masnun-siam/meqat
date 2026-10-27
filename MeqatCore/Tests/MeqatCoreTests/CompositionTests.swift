import XCTest
@testable import MeqatCore

final class CompositionTests: XCTestCase {
    private let dhaka = TimeZone(identifier: "Asia/Dhaka")!

    private func cache() throws -> TimingsCache {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TimingsCache.self, from: Fixture.data("engine/dhaka-2026-10-28-30.json"))
    }

    private func at(_ day: Int, _ h: Int, _ m: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = dhaka
        return c.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }

    func testEventsCoverCachedDaysAroundToday() throws {
        // Fixture holds Oct 28–30; asking on Oct 29 reaches yesterday (28) through 31, and 31 is missing.
        let list = Composition.events(cache: try cache(), settings: AppSettings(), now: at(29, 12, 0), timeZone: dhaka)
        XCTAssertEqual(Set(list.map(\.date)), [LocalDate(year: 2026, month: 10, day: 28), LocalDate(year: 2026, month: 10, day: 29), LocalDate(year: 2026, month: 10, day: 30)])
        XCTAssertEqual(list.count, 30)
    }

    func testNoCacheMeansNoEventsAndNoAlerts() {
        XCTAssertTrue(Composition.events(cache: nil, settings: AppSettings(), now: at(28, 12, 0), timeZone: dhaka).isEmpty)
        XCTAssertTrue(Composition.plan(cache: nil, settings: AppSettings(), now: at(28, 12, 0), timeZone: dhaka).isEmpty)
    }

    func testDefaultPlanIsBannersOnlyAndBounded() throws {
        let plan = Composition.plan(cache: try cache(), settings: AppSettings(), now: at(28, 0, 0), timeZone: dhaka)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertTrue(plan.allSatisfy { $0.style == .banner })
        XCTAssertLessThanOrEqual(plan.count, 60)
    }

    func testFetchParameters() {
        let s = AppSettings()
        let coords = Coordinates(latitude: 23.81, longitude: 90.41)
        XCTAssertEqual(Composition.fetchParameters(location: .located(coords), settings: s, timeZone: dhaka)?.location, .coordinates(coords))
        XCTAssertEqual(Composition.fetchParameters(location: .manual(city: "Dhaka", country: "Bangladesh", state: nil), settings: s, timeZone: dhaka)?.location,
                       .city(city: "Dhaka", country: "Bangladesh", state: nil))
        for state in [LocationState.awaitingPermission, .awaitingFix, .unavailable] {
            XCTAssertNil(Composition.fetchParameters(location: state, settings: s, timeZone: dhaka))
        }
    }

    func testMenuSyncInfoMapping() {
        var status = SyncStatus()
        status.isFetching = true
        status.lastFailure = .cityNotFound
        XCTAssertEqual(MenuSyncInfo(status), MenuSyncInfo(isFetching: true, lastFailure: .cityNotFound))
        status.lastFailure = .network
        XCTAssertEqual(MenuSyncInfo(status).lastFailure, .other)
        status.lastFailure = nil
        XCTAssertNil(MenuSyncInfo(status).lastFailure)
    }

    func testMenuLocationInfoMapping() {
        XCTAssertEqual(MenuLocationInfo(.awaitingPermission), .awaitingPermission)
        XCTAssertEqual(MenuLocationInfo(.awaitingFix), .awaitingFix)
        XCTAssertEqual(MenuLocationInfo(.located(Coordinates(latitude: 1, longitude: 2))), .available)
        XCTAssertEqual(MenuLocationInfo(.manual(city: "a", country: "b", state: nil)), .available)
        XCTAssertEqual(MenuLocationInfo(.unavailable), .missing)
    }

    func testIsStaleWhenCacheLocationBelongsToOtherMode() throws {
        var cache = try cache()
        cache.parameters.location = .coordinates(Coordinates(latitude: 1, longitude: 2))
        XCTAssertTrue(Composition.isStale(cache, mode: .manual))
        XCTAssertFalse(Composition.isStale(cache, mode: .automatic))
        cache.parameters.location = .city(city: "a", country: "b", state: nil)
        XCTAssertTrue(Composition.isStale(cache, mode: .automatic))
        cache.parameters.location = nil
        XCTAssertFalse(Composition.isStale(cache, mode: .manual))
    }
}
