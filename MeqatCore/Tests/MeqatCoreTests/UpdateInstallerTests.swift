import CryptoKit
import XCTest

@testable import MeqatCore

private let dmgBytes = Data(repeating: 7, count: 100)
private let dmgDigest = SHA256.hash(data: dmgBytes).map { String(format: "%02x", $0) }.joined()

private func makeRelease(_ tag: String, digest: String? = dmgDigest, asset: Bool = true) -> LatestRelease {
    let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    let url = URL(string: "https://github.com/masnun-siam/meqat/releases/download/\(tag)/Meqat-\(version).dmg")!
    return LatestRelease(
        tag: tag, pageURL: URL(string: "https://example.com/r")!,
        asset: asset ? ReleaseAsset(downloadURL: url, sha256: digest) : nil)
}

private actor StubReleases: ReleaseFetching {
    private(set) var calls = 0
    private var result = makeRelease("v1.8.0")
    private var holding = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func set(_ release: LatestRelease) { result = release }

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
        return result
    }
}

/// Sends `dmgBytes` in two chunks; `hold` keeps the body open after the first, as a slow download does.
private final class StubDownloads: DownloadTransport, @unchecked Sendable {
    var requests: [URLRequest] = []
    var status = 200
    var failure: Error?
    var hold = false

    func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<Data, Error>, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Length": String(dmgBytes.count)])!
        let stream = AsyncThrowingStream<Data, Error> { [failure, hold] continuation in
            continuation.yield(dmgBytes.prefix(50))
            guard !hold else { return }
            if let failure { return continuation.finish(throwing: failure) }
            continuation.yield(dmgBytes.suffix(50))
            continuation.finish()
        }
        return (stream, response)
    }
}

/// `hdiutil attach` creates the mount with a `Meqat.app` holding `plist`; `ditto` copies it; `codesign` returns
/// `codesignStatus`.
private final class FakeRunner: CommandRunning, @unchecked Sendable {
    var attachStatus: Int32 = 0
    var codesignStatus: Int32 = 0
    var dmgHasApp = true
    var bundleID = MeqatCore.bundleIdentifier
    var version = "1.8.0"
    var onCodesign: (@Sendable () async -> Void)?

    func run(_ executable: URL, _ arguments: [String]) async throws -> Int32 {
        switch executable.lastPathComponent {
        case "hdiutil" where arguments[0] == "attach":
            guard attachStatus == 0 else { return attachStatus }
            let mount = URL(fileURLWithPath: arguments[arguments.firstIndex(of: "-mountpoint")! + 1])
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            if dmgHasApp { try makeApp(at: mount.appendingPathComponent("Meqat.app"), id: bundleID, version: version) }
            return 0
        case "ditto":
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: arguments[1]), to: URL(fileURLWithPath: arguments[2]))
            return 0
        case "codesign":
            await onCodesign?()
            return codesignStatus
        default:
            return 0
        }
    }
}

private func makeApp(at app: URL, id: String, version: String) throws {
    let contents = app.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleShortVersionString": version]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: contents.appendingPathComponent("Info.plist"))
}

/// Real file moves; `failMoves` fails every move, `hold` blocks the first copy until `resume()`.
private final class FakeFiles: FileMoving, @unchecked Sendable {
    var failMoves = false
    var hold = false
    private(set) var copySources: [URL] = []
    private let gate = DispatchSemaphore(value: 0)
    private struct Injected: Error {}

    func resume() { gate.signal() }

    func url(
        for directory: FileManager.SearchPathDirectory, in domain: FileManager.SearchPathDomainMask,
        appropriateFor url: URL?, create shouldCreate: Bool
    ) throws -> URL {
        try FileManager.default.url(for: directory, in: domain, appropriateFor: url, create: shouldCreate)
    }

    func copyItem(at srcURL: URL, to dstURL: URL) throws {
        copySources.append(srcURL)
        if hold { gate.wait() }
        try FileManager.default.copyItem(at: srcURL, to: dstURL)
    }

    func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if failMoves { throw Injected() }
        try FileManager.default.moveItem(at: srcURL, to: dstURL)
    }

    func removeItem(at URL: URL) throws { try FileManager.default.removeItem(at: URL) }
}

private final class FakeLauncher: ProcessLaunching, @unchecked Sendable {
    var launches: [(executable: URL, arguments: [String])] = []
    var failure: Error?

    func launch(_ executable: URL, _ arguments: [String]) throws {
        if let failure { throw failure }
        launches.append((executable, arguments))
    }
}

@MainActor
final class UpdateInstallerTests: XCTestCase {
    private var dir: URL!
    private var temp: URL!
    private var appURL: URL!
    private var releases: StubReleases!
    private var downloads: StubDownloads!
    private var runner: FakeRunner!
    private var files: FakeFiles!
    private var launcher: FakeLauncher!
    private var terminations = 0
    private var installer: UpdateInstaller!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        temp = dir.appendingPathComponent("tmp")
        appURL = dir.appendingPathComponent("Applications/Meqat.app")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        try makeApp(at: appURL, id: MeqatCore.bundleIdentifier, version: "1.7.0")
        releases = StubReleases()
        downloads = StubDownloads()
        runner = FakeRunner()
        files = FakeFiles()
        launcher = FakeLauncher()
        terminations = 0
        installer = UpdateInstaller(
            installedVersion: "1.7.0", appURL: appURL, client: releases,
            downloader: UpdateDownloader(transport: downloads), extractor: DMGExtractor(runner: runner),
            replacer: BundleReplacer(files: files), runner: runner, launcher: launcher, temporaryDirectory: temp,
            terminate: { [unowned self] in self.terminations += 1 })
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func eventually(
        file: StaticString = #filePath, line: UInt = #line, _ condition: () async -> Bool
    ) async {
        for _ in 0..<2000 {
            if await condition() { return }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("condition not met", file: file, line: line)
    }

    private func settle() async {
        await eventually { !self.installer.isRunning || self.installer.state == .relaunching }
        // Lets the task finish its cleanup after the last state change.
        for _ in 0..<50 { await Task.yield() }
    }

    private var tempIsEmpty: Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: temp.path)) ?? ["?"]).isEmpty
    }

    private func installedVersion() -> String? {
        let data = try? Data(contentsOf: appURL.appendingPathComponent("Contents/Info.plist"))
        let plist = data.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) }
        return (plist as? [String: Any])?["CFBundleShortVersionString"] as? String
    }

    private func assertFails(
        file: StaticString = #filePath, line: UInt = #line, _ configure: () async -> Void
    ) async {
        await configure()
        installer.install()
        await settle()
        XCTAssertEqual(installer.state, .failed, file: file, line: line)
        XCTAssertTrue(tempIsEmpty, "work folder left", file: file, line: line)
        XCTAssertEqual(installedVersion(), "1.7.0", "installed app changed", file: file, line: line)
        XCTAssertEqual(terminations, 0, file: file, line: line)
        XCTAssertTrue(launcher.launches.isEmpty, file: file, line: line)
    }

    // MARK: - Happy path

    func testHappyPathInstallsRelaunchesAndQuits() async {
        let installer = installer!
        let seen = StateBox()
        runner.onCodesign = { await MainActor.run { seen.value = installer.state } }
        files.hold = true
        installer.install()
        XCTAssertEqual(installer.state, .downloading(percent: 0))
        await eventually { installer.state == .installing }
        XCTAssertEqual(seen.value, .verifying)
        files.resume()
        await settle()

        XCTAssertEqual(installer.state, .relaunching)
        XCTAssertEqual(files.copySources.map(\.lastPathComponent), ["Meqat.app"])
        XCTAssertEqual(files.copySources.first?.deletingLastPathComponent().deletingLastPathComponent().path, temp.path)
        XCTAssertEqual(installedVersion(), "1.8.0")
        XCTAssertEqual(launcher.launches.count, 1)
        XCTAssertEqual(launcher.launches.first?.executable.path, "/bin/sh")
        XCTAssertEqual(launcher.launches.first?.arguments.last, appURL.path)
        XCTAssertEqual(terminations, 1)
        XCTAssertTrue(tempIsEmpty)
    }

    func testDownloadReportsProgress() async {
        downloads.hold = true
        installer.install()
        await eventually { self.installer.state == .downloading(percent: 50) }
        installer.cancel()
    }

    // MARK: - Fresh release, one at a time

    func testEachInstallFetchesAFreshRelease() async {
        await releases.set(makeRelease("v1.8.0", digest: String(repeating: "0", count: 64)))
        installer.install()
        await settle()
        XCTAssertEqual(installer.state, .failed)

        await releases.set(makeRelease("v1.9.0"))
        runner.version = "1.9.0"
        installer.install()
        await settle()
        XCTAssertEqual(installer.state, .relaunching)
        let calls = await releases.calls
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(downloads.requests.last?.url?.lastPathComponent, "Meqat-1.9.0.dmg")
    }

    func testInstallWhileRunningDoesNothing() async {
        await releases.hold()
        installer.install()
        installer.install()
        await eventually { await self.releases.calls == 1 }
        installer.install()
        await releases.release()
        await settle()
        let calls = await releases.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(downloads.requests.count, 1)
        XCTAssertEqual(terminations, 1)
    }

    // MARK: - Failures

    func testNotNewerFailsWithoutDownload() async {
        await assertFails { await self.releases.set(makeRelease("v1.7.0")) }
        XCTAssertTrue(downloads.requests.isEmpty)
    }

    func testNoAssetFailsWithoutDownload() async {
        await assertFails { await self.releases.set(makeRelease("v1.8.0", asset: false)) }
        XCTAssertTrue(downloads.requests.isEmpty)
    }

    func testDownloadNon200Fails() async {
        await assertFails { self.downloads.status = 404 }
    }

    func testDownloadTimeoutFails() async {
        await assertFails { self.downloads.failure = URLError(.timedOut) }
    }

    func testDigestMismatchFails() async {
        await assertFails { await self.releases.set(makeRelease("v1.8.0", digest: String(repeating: "0", count: 64))) }
    }

    func testMissingDigestFails() async {
        await assertFails { await self.releases.set(makeRelease("v1.8.0", digest: nil)) }
    }

    func testAttachFailureFails() async {
        await assertFails { self.runner.attachStatus = 1 }
    }

    func testAppMissingFails() async {
        await assertFails { self.runner.dmgHasApp = false }
    }

    func testWrongBundleIDFails() async {
        await assertFails { self.runner.bundleID = "com.example.Other" }
    }

    func testWrongVersionFails() async {
        await assertFails { self.runner.version = "1.9.0" }
    }

    func testBadSignatureFails() async {
        await assertFails { self.runner.codesignStatus = 1 }
    }

    func testReplaceFailureFailsAndKeepsInstalledApp() async {
        await assertFails { self.files.failMoves = true }
        XCTAssertEqual(files.copySources.count, 1)
    }

    func testRelaunchFailureFailsWithoutQuitting() async {
        launcher.failure = CocoaError(.fileNoSuchFile)
        installer.install()
        await settle()
        XCTAssertEqual(installer.state, .failed)
        XCTAssertEqual(terminations, 0)
        XCTAssertTrue(tempIsEmpty)
    }

    func testRetryAfterFailure() async {
        downloads.status = 500
        installer.install()
        await settle()
        XCTAssertEqual(installer.state, .failed)

        downloads.status = 200
        installer.install()
        await settle()
        XCTAssertEqual(installer.state, .relaunching)
        XCTAssertEqual(terminations, 1)
    }

    // MARK: - Cancel and quit

    func testCancelMidDownloadReturnsToIdle() async {
        downloads.hold = true
        installer.install()
        await eventually { self.installer.state == .downloading(percent: 50) }
        installer.cancel()
        XCTAssertEqual(installer.state, .idle)
        await eventually { self.tempIsEmpty }
        XCTAssertTrue(files.copySources.isEmpty)
        XCTAssertEqual(installer.state, .idle)
    }

    func testCancelOutsideDownloadOrVerifyDoesNothing() async {
        installer.cancel()
        XCTAssertEqual(installer.state, .idle)
        downloads.status = 500
        installer.install()
        await settle()
        installer.cancel()
        XCTAssertEqual(installer.state, .failed)
    }

    func testPrepareToQuitWhileDownloadingCancels() async {
        downloads.hold = true
        installer.install()
        await eventually { self.installer.state == .downloading(percent: 50) }
        await installer.prepareToQuit()
        XCTAssertEqual(installer.state, .idle)
        XCTAssertTrue(tempIsEmpty)
        XCTAssertTrue(files.copySources.isEmpty)
    }

    func testPrepareToQuitWhileInstallingWaitsForTheSwap() async {
        files.hold = true
        installer.install()
        await eventually { self.installer.state == .installing }

        let done = StateBox()
        let quit = Task {
            await self.installer.prepareToQuit(); done.finished = true
        }
        for _ in 0..<50 { await Task.yield() }
        XCTAssertFalse(done.finished)

        files.resume()
        await quit.value
        XCTAssertEqual(installedVersion(), "1.8.0")
        XCTAssertNotEqual(installer.state, .installing)
    }

    func testPrepareToQuitWhileIdleReturnsAtOnce() async {
        await installer.prepareToQuit()
        XCTAssertEqual(installer.state, .idle)
        let calls = await releases.calls
        XCTAssertEqual(calls, 0)
    }

    // MARK: - Log kinds

    func testKindsAreListedAndHoldNoURLOrPath() {
        let cases: [(Error, String)] = [
            (InstallError.notNewer, "no newer release"),
            (InstallError.noAsset, "no asset"),
            (InstallError.relaunchFailed, "relaunch failed"),
            (ReleaseError.http(403), "release check http 403"),
            (ReleaseError.bodyTooLarge, "release check too large"),
            (ReleaseError.invalidResponse, "invalid response"),
            (DownloadError.insecureURL, "download insecure"),
            (DownloadError.http(404), "download http 404"),
            (DownloadError.tooLarge, "download too large"),
            (DownloadError.writeFailed, "download write failed"),
            (
                URLError(.timedOut, userInfo: [NSURLErrorFailingURLErrorKey: URL(string: "https://x.y/z")!]),
                "connection error"
            ),
            (UpdateVerificationError.missingDigest, "missing digest"),
            (UpdateVerificationError.digestMismatch, "digest mismatch"),
            (UpdateVerificationError.unreadableBundle, "unreadable bundle"),
            (UpdateVerificationError.wrongBundleID, "wrong bundle id"),
            (UpdateVerificationError.wrongVersion, "wrong version"),
            (UpdateVerificationError.badSignature, "bad signature"),
            (DMGError.attachFailed, "dmg attach failed"),
            (DMGError.appMissing, "app missing"),
            (DMGError.copyFailed, "copy failed"),
            (BundleReplaceError.stagingFailed, "staging failed"),
            (BundleReplaceError.swapFailed, "swap failed"),
            (CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "/Applications/Meqat.app"]), "other error"),
        ]
        for (error, kind) in cases {
            let logged = UpdateInstaller.kind(of: error)
            XCTAssertEqual(logged, kind)
            XCTAssertFalse(logged.contains("/") || logged.contains("://"), logged)
        }
    }
}

private final class StateBox: @unchecked Sendable {
    var value: InstallState?
    var finished = false
}
