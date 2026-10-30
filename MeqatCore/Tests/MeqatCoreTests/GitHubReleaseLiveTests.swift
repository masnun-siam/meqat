import XCTest

@testable import MeqatCore

final class GitHubReleaseLiveTests: XCTestCase {
    func testLiveLatestRelease() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MEQAT_LIVE_TESTS"] == "1")
        let release = try await GitHubReleaseClient().fetchLatest()
        XCTAssertFalse(release.tag.isEmpty)
        XCTAssertTrue(release.pageURL.absoluteString.hasPrefix("https://github.com/masnun-siam/meqat/releases/tag/"))
    }
}
