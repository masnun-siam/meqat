import XCTest
@testable import MeqatCore

final class TimingsCacheTests: XCTestCase {
    private var dir: URL!
    private var store: CacheStore!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = CacheStore(directory: dir)
    }

    override func tearDown() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }

    private func day(_ date: LocalDate) -> DayTimings {
        let base = date.startOfDay(in: TimeZone(identifier: "UTC")!)
        func t(_ h: Double) -> Date { base.addingTimeInterval(h * 3600) }
        return DayTimings(date: date, fajr: t(5), sunrise: t(6), dhuhr: t(12), asr: t(15), sunset: t(18),
                          maghrib: t(18.05), isha: t(19.5), midnight: t(23.5), lastthird: t(26))
    }

    private func cache(_ location: FetchLocation?, days: [LocalDate] = [LocalDate(year: 2026, month: 10, day: 30), LocalDate(year: 2026, month: 10, day: 31)]) -> TimingsCache {
        TimingsCache(parameters: FetchParameters(location: location, method: nil, school: 1, timeZoneId: "Asia/Dhaka"),
                     fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
                     days: Dictionary(uniqueKeysWithValues: days.map { ($0, day($0)) }))
    }

    func testRoundTrip() throws {
        for location in [FetchLocation.coordinates(.init(latitude: 23.81, longitude: 90.41)),
                         .city(city: "Dhaka", country: "BD", state: nil),
                         .city(city: "Austin", country: "US", state: "TX")] {
            let original = cache(location)
            try store.save(original)
            XCTAssertEqual(store.load(), original)
        }
    }

    func testFlatKeys() throws {
        try store.save(cache(.coordinates(.init(latitude: 1.5, longitude: 2.5))))
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("timings.json"))) as! [String: Any]
        XCTAssertEqual(json["latitude"] as? Double, 1.5)
        XCTAssertTrue(json["city"] is NSNull)
        XCTAssertTrue(json["method"] is NSNull)
    }

    func testBadFilesAreDeleted() throws {
        let file = dir.appendingPathComponent("timings.json")
        try store.save(cache(nil))
        var wrong = cache(nil)
        wrong.formatVersion = 99
        try store.save(wrong)
        XCTAssertNil(store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))

        try Data("garbage".utf8).write(to: file)
        XCTAssertNil(store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testFailedSaveKeepsOldFile() throws {
        let a = cache(.city(city: "Dhaka", country: "BD", state: nil))
        try store.save(a)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        XCTAssertThrowsError(try store.save(cache(.city(city: "Austin", country: "US", state: "TX"))))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        XCTAssertEqual(store.load(), a)
    }

    func testCovers() {
        let d = LocalDate(year: 2026, month: 10, day: 30)
        let full = cache(nil, days: (0..<3).map { d.adding(days: $0) })
        XCTAssertTrue(full.covers(from: d, through: d.adding(days: 2)))
        XCTAssertFalse(full.covers(from: d, through: d.adding(days: 3)))
        let gap = cache(nil, days: [d, d.adding(days: 2)])
        XCTAssertFalse(gap.covers(from: d, through: d.adding(days: 2)))
    }

    func testStrippingLocation() {
        let original = cache(.coordinates(.init(latitude: 1, longitude: 2)))
        let stripped = original.strippingLocation()
        XCTAssertNil(stripped.parameters.location)
        XCTAssertEqual(stripped.days, original.days)
        XCTAssertEqual(stripped.parameters.method, original.parameters.method)
        XCTAssertEqual(stripped.parameters.school, original.parameters.school)
        XCTAssertEqual(stripped.parameters.timeZoneId, original.parameters.timeZoneId)
    }

    func testLocalDate() {
        XCTAssertEqual(LocalDate(year: 2026, month: 1, day: 31).adding(days: 1), LocalDate(year: 2026, month: 2, day: 1))
        XCTAssertEqual(LocalDate(year: 2026, month: 12, day: 31).adding(days: 1), LocalDate(year: 2027, month: 1, day: 1))
        XCTAssertEqual(LocalDate(year: 2026, month: 10, day: 30).weekday, 6)
    }
}
