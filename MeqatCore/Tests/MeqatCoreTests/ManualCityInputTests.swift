import XCTest

@testable import MeqatCore

final class ManualCityInputTests: XCTestCase {
    func testTrims() {
        let r = ManualCityInput.normalized(city: "  Dhaka  ", country: "Bangladesh", state: "")
        XCTAssertEqual(r?.city, "Dhaka")
        XCTAssertEqual(r?.country, "Bangladesh")
        XCTAssertNil(r?.state)
    }

    func testEmptyCityOrCountryIsNil() {
        XCTAssertNil(ManualCityInput.normalized(city: "  ", country: "BD", state: ""))
        XCTAssertNil(ManualCityInput.normalized(city: "Dhaka", country: "\n", state: ""))
    }

    func testWhitespaceStateIsNil() {
        XCTAssertNil(ManualCityInput.normalized(city: "A", country: "B", state: "  ")?.state)
        XCTAssertEqual(ManualCityInput.normalized(city: "A", country: "B", state: " Dhaka ")?.state, "Dhaka")
    }

    func testCutsTo100() {
        let long = String(repeating: "a", count: 150)
        let r = ManualCityInput.normalized(city: long, country: long, state: long)
        XCTAssertEqual(r?.city.count, 100)
        XCTAssertEqual(r?.country.count, 100)
        XCTAssertEqual(r?.state?.count, 100)
    }

    func testNonASCIIPassesThrough() {
        XCTAssertEqual(ManualCityInput.normalized(city: "São Paulo", country: "Brasil", state: "")?.city, "São Paulo")
    }
}
