import XCTest

@testable import MeqatCore

private actor StubReleases: ReleaseFetching {
    private(set) var calls = 0
    private var result = LatestRelease(tag: "v1.3.0", pageURL: URL(string: "https://example.com/r")!)
    private var failure: Error?
    private var holding = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func setTag(_ tag: String) { result = LatestRelease(tag: tag, pageURL: result.pageURL) }

    func fail(with error: Error?) { failure = error }

    func hold() { holding = true }

    func release() {
        holding = false
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }

    func fetchLatest() async throws -> LatestRelease {
        calls += 1
        if holding { await withCheckedContinuation { waiters.append($0) } }
        if let failure { throw failure }
        return result
    }
}

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_792_065_600)  // 2026-10-15 12:00 UTC
    private let url = URL(string: "https://example.com/r")!
    private var stub: StubReleases!
    private var checker: UpdateChecker!

    override func setUp() async throws {
        stub = StubReleases()
        let date = fixedNow
        checker = UpdateChecker(installedVersion: "1.3.0", client: stub, now: { date })
    }

    private func eventually(
        file: StaticString = #filePath, line: UInt = #line, _ condition: () async -> Bool
    ) async {
        for _ in 0..<1000 {
            if await condition() { return }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("condition not met", file: file, line: line)
    }

    private func settle(_ trigger: UpdateCheckTrigger) async {
        checker.check(trigger)
        await eventually { self.checker.status != .checking }
    }

    func testStartsIdle() {
        XCTAssertEqual(checker.status, .idle)
    }

    func testCheckingImmediately() async {
        await stub.hold()
        checker.check(.automatic)
        XCTAssertEqual(checker.status, .checking)
        await stub.release()
        await eventually { self.checker.status != .checking }
    }

    func testNewerTagIsAvailable() async {
        await stub.setTag("v1.4.0")
        await settle(.manual)
        XCTAssertEqual(checker.status, .available(version: "1.4.0", releaseURL: url))
    }

    func testSameNightlyAndOlderAreUpToDate() async {
        for tag in ["v1.3.0", "nightly", "v1.2.0"] {
            await stub.setTag(tag)
            await settle(.automatic)
            XCTAssertEqual(checker.status, .upToDate(checkedAt: fixedNow), tag)
        }
    }

    func testAutomaticFailureRestoresPreviousStatus() async {
        await stub.fail(with: ReleaseError.http(403))
        await settle(.automatic)
        XCTAssertEqual(checker.status, .idle)

        await stub.fail(with: nil)
        await stub.setTag("v1.4.0")
        await settle(.automatic)
        await stub.fail(with: URLError(.notConnectedToInternet))
        await settle(.automatic)
        XCTAssertEqual(checker.status, .available(version: "1.4.0", releaseURL: url))

        await stub.setTag("v1.3.0")
        await stub.fail(with: nil)
        await settle(.automatic)
        await stub.fail(with: ReleaseError.invalidResponse)
        await settle(.automatic)
        XCTAssertEqual(checker.status, .upToDate(checkedAt: fixedNow))

        await settle(.manual)
        XCTAssertEqual(checker.status, .failed)
        await settle(.automatic)
        XCTAssertEqual(checker.status, .failed)
    }

    func testManualFailureIsFailed() async {
        await stub.fail(with: ReleaseError.http(500))
        await settle(.manual)
        XCTAssertEqual(checker.status, .failed)
    }

    func testConcurrentChecksShareOneRequest() async {
        await stub.hold()
        checker.check(.automatic)
        checker.check(.automatic)
        await stub.release()
        await eventually { self.checker.status != .checking }
        let calls = await stub.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(checker.status, .upToDate(checkedAt: fixedNow))
    }

    func testManualJoinerMakesFailureVisible() async {
        await stub.fail(with: ReleaseError.http(403))
        await stub.hold()
        checker.check(.automatic)
        checker.check(.manual)
        await stub.release()
        await eventually { self.checker.status != .checking }
        XCTAssertEqual(checker.status, .failed)
    }

    func testNextCheckAfterCompletionRequestsAgain() async {
        await settle(.automatic)
        await settle(.automatic)
        let calls = await stub.calls
        XCTAssertEqual(calls, 2)
    }
}
