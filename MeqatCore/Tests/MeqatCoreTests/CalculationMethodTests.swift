import XCTest
@testable import MeqatCore

final class CalculationMethodTests: XCTestCase {
    func testIdsAreUniqueAndExcludeSixAndCustom() {
        let ids = CalculationMethod.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertFalse(ids.contains(6))
        XCTAssertFalse(ids.contains(99))
    }

    func testHas23Entries() {
        XCTAssertEqual(CalculationMethod.all.count, 23)
    }
}
