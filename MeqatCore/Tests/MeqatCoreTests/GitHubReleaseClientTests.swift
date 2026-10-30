import XCTest

@testable import MeqatCore

final class GitHubReleaseClientTests: XCTestCase {
    func fetch(_ body: String, status: Int = 200) async throws -> LatestRelease {
        try await GitHubReleaseClient(transport: StubTransport(status: status, body: Data(body.utf8))).fetchLatest()
    }

    func assertThrows(_ expected: ReleaseError, _ body: String, status: Int = 200, line: UInt = #line) async {
        do {
            _ = try await fetch(body, status: status)
            XCTFail("expected error", line: line)
        } catch { XCTAssertEqual(error as? ReleaseError, expected, line: line) }
    }

    func testRequest() async throws {
        let r = GitHubReleaseClient.request()
        XCTAssertEqual(r.url?.absoluteString, "https://api.github.com/repos/masnun-siam/meqat/releases/latest")
        XCTAssertEqual(r.httpMethod ?? "GET", "GET")
        XCTAssertEqual(r.timeoutInterval, 5)
        XCTAssertEqual(r.allHTTPHeaderFields, ["Accept": "application/vnd.github+json", "User-Agent": "Meqat"])
        let t = StubTransport(status: 200, body: Data(#"{"tag_name":"v1","html_url":"https://x.y/z"}"#.utf8))
        _ = try await GitHubReleaseClient(transport: t).fetchLatest()
        XCTAssertEqual(t.requests, [r])
    }

    func testValidBodyIgnoresOtherFields() async throws {
        let release = try await fetch(
            #"{"tag_name":"v1.4.0","html_url":"https://github.com/masnun-siam/meqat/releases/tag/v1.4.0","id":7,"assets":[]}"#)
        XCTAssertEqual(release.tag, "v1.4.0")
        XCTAssertEqual(release.pageURL.absoluteString, "https://github.com/masnun-siam/meqat/releases/tag/v1.4.0")
    }

    func testInvalidBodies() async {
        for body in [
            #"{"html_url":"https://x.y"}"#,
            #"{"tag_name":"v1"}"#,
            #"{"tag_name":1,"html_url":"https://x.y"}"#,
            #"{"tag_name":"v1","html_url":"not a url"}"#,
            #"{"tag_name":"v1","html_url":"http://x.y"}"#,
            "{not json",
        ] { await assertThrows(.invalidResponse, body) }
    }

    func testBodyTooLarge() async {
        await assertThrows(.bodyTooLarge, String(repeating: " ", count: GitHubReleaseClient.maxBodyBytes + 1))
    }

    func testNon200() async {
        for status in [403, 404, 429, 500] { await assertThrows(.http(status), "{}", status: status) }
    }

    func testTransportErrorRethrown() async {
        let client = GitHubReleaseClient(transport: StubTransport(.failure(URLError(.timedOut))))
        do {
            _ = try await client.fetchLatest()
            XCTFail()
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
    }
}
