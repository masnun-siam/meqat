import CryptoKit
import XCTest

@testable import MeqatCore

private final class FakeRunner: CommandRunning, @unchecked Sendable {
    var status: Int32 = 0
    var calls: [(executable: URL, arguments: [String])] = []

    func run(_ executable: URL, _ arguments: [String]) async throws -> Int32 {
        calls.append((executable, arguments))
        return status
    }
}

final class UpdateVerifierTests: XCTestCase {
    private var dir: URL!
    private var runner: FakeRunner!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        runner = FakeRunner()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Digest

    private func dmg() throws -> (URL, String) {
        let data = Data("meqat update".utf8)
        let url = dir.appendingPathComponent("Meqat.dmg")
        try data.write(to: url)
        return (url, SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

    func testDigestMatches() throws {
        let (url, hash) = try dmg()
        XCTAssertNoThrow(try UpdateVerifier.verifyDigest(of: url, expected: hash))
    }

    func testDigestMatchesUppercase() throws {
        let (url, hash) = try dmg()
        XCTAssertNoThrow(try UpdateVerifier.verifyDigest(of: url, expected: hash.uppercased()))
    }

    func testMissingDigestFails() throws {
        let (url, _) = try dmg()
        XCTAssertThrowsError(try UpdateVerifier.verifyDigest(of: url, expected: nil)) {
            XCTAssertEqual($0 as? UpdateVerificationError, .missingDigest)
        }
    }

    func testDifferentDigestFails() throws {
        let (url, hash) = try dmg()
        let other = String(hash.dropLast()) + (hash.hasSuffix("0") ? "1" : "0")
        XCTAssertThrowsError(try UpdateVerifier.verifyDigest(of: url, expected: other)) {
            XCTAssertEqual($0 as? UpdateVerificationError, .digestMismatch)
        }
    }

    func testDigestPrefixFails() throws {
        let (url, hash) = try dmg()
        XCTAssertThrowsError(try UpdateVerifier.verifyDigest(of: url, expected: String(hash.prefix(16)))) {
            XCTAssertEqual($0 as? UpdateVerificationError, .digestMismatch)
        }
    }

    // MARK: - App

    private func app(plist: Any?) throws -> URL {
        let app = dir.appendingPathComponent("Meqat.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        if let plist {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
        }
        return app
    }

    private func info(id: String = "com.masnunsiam.Meqat", version: String = "1.8.0") -> [String: Any] {
        ["CFBundleIdentifier": id, "CFBundleShortVersionString": version]
    }

    private func assertVerifyApp(
        _ app: URL, throws expected: UpdateVerificationError, file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            try await UpdateVerifier.verifyApp(at: app, version: "1.8.0", runner: runner)
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? UpdateVerificationError, expected, file: file, line: line)
        }
    }

    func testValidAppPassesAndRunsCodesign() async throws {
        let app = try app(plist: info())
        try await UpdateVerifier.verifyApp(at: app, version: "1.8.0", runner: runner)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls.first?.executable.path, "/usr/bin/codesign")
        XCTAssertEqual(runner.calls.first?.arguments, ["--verify", "--deep", "--strict", app.path])
    }

    func testWrongBundleIDFailsWithoutCodesign() async throws {
        await assertVerifyApp(try app(plist: info(id: "com.example.Other")), throws: .wrongBundleID)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testWrongVersionFailsWithoutCodesign() async throws {
        await assertVerifyApp(try app(plist: info(version: "1.7.9")), throws: .wrongVersion)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testMissingPlistIsUnreadable() async throws {
        await assertVerifyApp(try app(plist: nil), throws: .unreadableBundle)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testNonDictionaryPlistIsUnreadable() async throws {
        await assertVerifyApp(try app(plist: ["not", "a", "dictionary"]), throws: .unreadableBundle)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testNonZeroCodesignIsBadSignature() async throws {
        runner.status = 1
        await assertVerifyApp(try app(plist: info()), throws: .badSignature)
        XCTAssertEqual(runner.calls.count, 1)
    }

    // MARK: - ProcessCommandRunner

    func testProcessRunnerReturnsExitStatus() async throws {
        let real = ProcessCommandRunner()
        let ok = try await real.run(URL(fileURLWithPath: "/usr/bin/true"), [])
        let fail = try await real.run(URL(fileURLWithPath: "/usr/bin/false"), [])
        XCTAssertEqual(ok, 0)
        XCTAssertEqual(fail, 1)
    }

    func testProcessRunnerThrowsForMissingExecutable() async {
        do {
            _ = try await ProcessCommandRunner().run(URL(fileURLWithPath: "/nonexistent/tool"), [])
            XCTFail("expected an error")
        } catch {}
    }
}
