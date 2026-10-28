import XCTest

@testable import MeqatCore

final class SmokeTests: XCTestCase {
    func testBundleIdentifier() {
        XCTAssertEqual(MeqatCore.bundleIdentifier, "com.masnunsiam.Meqat")
    }
}
