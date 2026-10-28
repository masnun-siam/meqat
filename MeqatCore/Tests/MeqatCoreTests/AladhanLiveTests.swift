import XCTest

@testable import MeqatCore

final class AladhanLiveTests: XCTestCase {
    func testLiveBothEndpoints() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MEQAT_LIVE_TESTS"] == "1")
        let client = AladhanClient()
        let now = LocalDate(Date(), timeZone: TimeZone(identifier: "Asia/Dhaka")!).yearMonth
        func p(_ l: FetchLocation, school: Int = 0) -> FetchParameters {
            FetchParameters(location: l, method: nil, school: school, timeZoneId: "Asia/Dhaka")
        }
        let byCoords = p(.coordinates(Coordinates(latitude: 23.81, longitude: 90.41)))
        let byCity = p(.city(city: "Dhaka", country: "Bangladesh", state: nil))
        for params in [byCoords, byCity] {
            let days = try await client.fetchMonth(now, parameters: params)
            XCTAssertFalse(days.isEmpty)
            let tz = TimeZone(identifier: "Asia/Dhaka")!
            for d in days {
                XCTAssertEqual(LocalDate(d.lastthird, timeZone: tz), d.date.adding(days: 1), "\(d.date)")
            }
        }
        let shafii = try await client.fetchMonth(now, parameters: byCoords)
        let hanafi = try await client.fetchMonth(now, parameters: p(byCoords.location!, school: 1))
        XCTAssertGreaterThan(hanafi[0].asr, shafii[0].asr)
    }
}
