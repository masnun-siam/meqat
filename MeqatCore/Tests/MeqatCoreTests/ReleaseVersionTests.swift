import XCTest

@testable import MeqatCore

final class ReleaseVersionTests: XCTestCase {
    func testNewerTagReportsItsVersion() {
        XCTAssertEqual(ReleaseVersion.newer(tag: "v1.4.0", than: "1.3.0")?.description, "1.4.0")
    }

    func testSameVersionIsNotNewer() {
        XCTAssertNil(ReleaseVersion.newer(tag: "v1.3.0", than: "1.3.0"))
    }

    func testComparesNumerically() {
        XCTAssertNotNil(ReleaseVersion.newer(tag: "v1.10.0", than: "1.9.0"))
        XCTAssertGreaterThan(ReleaseVersion("1.10.0")!, ReleaseVersion("1.9.0")!)
        XCTAssertGreaterThan(ReleaseVersion("2.0.0")!, ReleaseVersion("1.99.99")!)
    }

    func testMalformedTagsAreNeverNewer() {
        for tag in ["nightly", "v1.4", "1.4.0-beta", "v1.4.0.1", "v-1.4.0", "V1.4.0", "", "1..2", "v1.4.x", "1.4.0 "] {
            XCTAssertNil(ReleaseVersion.newer(tag: tag, than: "1.3.0"), tag)
        }
    }

    func testOlderTagIsNotNewer() {
        XCTAssertNil(ReleaseVersion.newer(tag: "v1.2.0", than: "1.3.0"))
    }

    func testMalformedInstalledMakesNothingNewer() {
        XCTAssertNil(ReleaseVersion.newer(tag: "v1.4.0", than: "dev"))
        XCTAssertNil(ReleaseVersion.newer(tag: "v1.4.0", than: ""))
    }

    func testOverflowFails() {
        XCTAssertNil(ReleaseVersion("99999999999999999999.0.0"))
    }

    func testDescriptionDropsLeadingV() {
        XCTAssertEqual(ReleaseVersion("v1.4.0")?.description, "1.4.0")
    }
}
