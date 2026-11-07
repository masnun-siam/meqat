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

    static let hex = String(repeating: "aB3", count: 21) + "f"
    static let dmgURL = "https://github.com/masnun-siam/meqat/releases/download/v1.8.0/Meqat-1.8.0.dmg"

    func release(tag: String = "v1.8.0", assets: String) async throws -> LatestRelease {
        try await fetch(
            #"{"tag_name":"\#(tag)","html_url":"https://github.com/masnun-siam/meqat/releases/tag/v1.8.0","assets":\#(assets)}"#)
    }

    func dmg(name: String = "Meqat-1.8.0.dmg", url: String = dmgURL, digest: String? = "\"sha256:\(hex)\"") -> String {
        let digestField = digest.map { #","digest":\#($0)"# } ?? ""
        return #"{"name":"\#(name)","browser_download_url":"\#(url)"\#(digestField)}"#
    }

    func testDmgAssetReturnedWithLowercasedDigest() async throws {
        let r = try await release(assets: "[\(dmg(name: "Meqat-1.8.0.zip")),\(dmg())]")
        XCTAssertEqual(r.asset?.downloadURL.absoluteString, Self.dmgURL)
        XCTAssertEqual(r.asset?.sha256, Self.hex.lowercased())
        XCTAssertEqual(r.asset?.sha256?.count, 64)
    }

    func testNoAssetWithoutMatchingDmg() async throws {
        let base = #"{"tag_name":"v1.8.0","html_url":"https://github.com/masnun-siam/meqat/releases/tag/v1.8.0"}"#
        let missing = try await fetch(base)
        XCTAssertNil(missing.asset)
        for assets in [
            "[]", "null", "[\(dmg(name: "Meqat-1.7.0.dmg"))]", "[\(dmg(name: "Meqat.dmg"))]",
            "[\(dmg(name: "Meqat-v1.8.0.dmg"))]", "[null, 3]", #""nope""#,
        ] {
            let r = try await release(assets: assets)
            XCTAssertNil(r.asset, assets)
            XCTAssertEqual(r.tag, "v1.8.0")
        }
    }

    func testNoAssetForNonSemverTag() async throws {
        for tag in ["latest", "v1.8", "1.8.0-beta"] {
            let r = try await release(tag: tag, assets: "[\(dmg(name: "Meqat-\(tag).dmg"))]")
            XCTAssertNil(r.asset, tag)
            XCTAssertEqual(r.tag, tag)
        }
    }

    func testNoAssetForUntrustedURL() async throws {
        for url in [
            "http://github.com/a/Meqat-1.8.0.dmg", "https://evil.example/Meqat-1.8.0.dmg",
            "https://github.com.evil.example/x.dmg", "not a url", "",
        ] {
            let r = try await release(assets: "[\(dmg(url: url))]")
            XCTAssertNil(r.asset, url)
        }
        let wrongType = try await release(assets: #"[{"name":"Meqat-1.8.0.dmg","browser_download_url":7}]"#)
        XCTAssertNil(wrongType.asset)
    }

    func testMalformedDigestKeepsAsset() async throws {
        let digests: [String?] = [
            nil, "null", "7", #""sha512:\#(Self.hex)""#, #""\#(Self.hex)""#, #""sha256:\#(Self.hex.dropLast())""#,
            #""sha256:\#(Self.hex)0""#, #""sha256:\#(Self.hex.dropLast())g""#, #""SHA256:\#(Self.hex)""#,
        ]
        for digest in digests {
            let r = try await release(assets: "[\(dmg(digest: digest))]")
            XCTAssertEqual(r.asset?.downloadURL.absoluteString, Self.dmgURL, digest ?? "missing")
            XCTAssertNil(r.asset?.sha256, digest ?? "missing")
        }
    }

    func testFullwidthHexDigestRejected() async throws {
        let fullwidth = String(repeating: "\u{FF41}", count: 64)
        let r = try await release(assets: "[\(dmg(digest: #""sha256:\#(fullwidth)""#))]")
        XCTAssertNotNil(r.asset)
        XCTAssertNil(r.asset?.sha256)
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
