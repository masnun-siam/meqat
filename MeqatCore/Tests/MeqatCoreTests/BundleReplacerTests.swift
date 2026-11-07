import XCTest

@testable import MeqatCore

final class BundleReplacerTests: XCTestCase {
    private enum Method { case url, copy, move, remove }
    private struct InjectedFailure: Error {}

    /// Forwards to `FileManager.default` and throws on the Nth call of one method.
    private final class FailingFiles: FileMoving {
        let method: Method?
        let failingCalls: Set<Int>
        private var calls: [Method: Int] = [:]
        private(set) var stagingURL: URL?

        init(failing method: Method? = nil, onCalls failingCalls: Set<Int> = [1]) {
            self.method = method
            self.failingCalls = failingCalls
        }

        private func tick(_ called: Method) throws {
            calls[called, default: 0] += 1
            if called == method, failingCalls.contains(calls[called]!) { throw InjectedFailure() }
        }

        func url(
            for directory: FileManager.SearchPathDirectory, in domain: FileManager.SearchPathDomainMask,
            appropriateFor url: URL?, create shouldCreate: Bool
        ) throws -> URL {
            try tick(.url)
            let staging = try FileManager.default.url(
                for: directory, in: domain, appropriateFor: url, create: shouldCreate)
            stagingURL = staging
            return staging
        }

        func copyItem(at srcURL: URL, to dstURL: URL) throws {
            try tick(.copy)
            try FileManager.default.copyItem(at: srcURL, to: dstURL)
        }

        func moveItem(at srcURL: URL, to dstURL: URL) throws {
            try tick(.move)
            try FileManager.default.moveItem(at: srcURL, to: dstURL)
        }

        func removeItem(at URL: URL) throws {
            try tick(.remove)
            try FileManager.default.removeItem(at: URL)
        }
    }

    private var dir: URL!
    private var installed: URL!
    private var newApp: URL!
    private var original: [String: Data]!
    private var update: [String: Data]!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let applications = dir.appendingPathComponent("Applications")
        let download = dir.appendingPathComponent("Download")
        installed = applications.appendingPathComponent("Meqat.app")
        newApp = download.appendingPathComponent("Meqat.app")
        try makeApp(at: installed, version: "1.7.0", binary: Data([1, 7, 0]))
        try makeApp(at: newApp, version: "1.8.0", binary: Data([1, 8, 0, 42]))
        original = try snapshot(installed)
        update = try snapshot(newApp)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeApp(at app: URL, version: String, binary: Data) throws {
        let contents = app.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let plist = ["CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try binary.write(to: macOS.appendingPathComponent("Meqat"))
    }

    /// Every regular file under `app`, by relative path.
    private func snapshot(_ app: URL) throws -> [String: Data] {
        let root = app.resolvingSymlinksInPath().path + "/"
        var files: [String: Data] = [:]
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where !url.hasDirectoryPath {
            let path = url.resolvingSymlinksInPath().path
            files[String(path.dropFirst(root.count))] = try Data(contentsOf: url)
        }
        return files
    }

    private func parentContents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: installed.deletingLastPathComponent().path)
    }

    private func replace(_ files: FailingFiles) throws {
        try BundleReplacer(files: files).replace(installed, with: newApp)
    }

    private func assertStagingRemoved(_ files: FailingFiles, file: StaticString = #filePath, line: UInt = #line) {
        guard let staging = files.stagingURL else { return XCTFail("no staging folder", file: file, line: line) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path), file: file, line: line)
    }

    func testSuccessReplacesBundleAndRemovesStaging() throws {
        let files = FailingFiles()
        try replace(files)
        XCTAssertEqual(try snapshot(installed), update)
        XCTAssertEqual(try parentContents(), ["Meqat.app"])
        assertStagingRemoved(files)
    }

    func testStagingFolderFailureLeavesOriginal() throws {
        XCTAssertThrowsError(try replace(FailingFiles(failing: .url))) {
            XCTAssertEqual($0 as? BundleReplaceError, .stagingFailed)
        }
        XCTAssertEqual(try snapshot(installed), original)
        XCTAssertEqual(try parentContents(), ["Meqat.app"])
    }

    func testCopyFailureLeavesOriginalAndRemovesStaging() throws {
        let files = FailingFiles(failing: .copy)
        XCTAssertThrowsError(try replace(files)) { XCTAssertEqual($0 as? BundleReplaceError, .stagingFailed) }
        XCTAssertEqual(try snapshot(installed), original)
        assertStagingRemoved(files)
    }

    func testMoveOldAsideFailureLeavesOriginalAndRemovesStaging() throws {
        let files = FailingFiles(failing: .move, onCalls: [1])
        XCTAssertThrowsError(try replace(files)) { XCTAssertEqual($0 as? BundleReplaceError, .swapFailed) }
        XCTAssertEqual(try snapshot(installed), original)
        assertStagingRemoved(files)
    }

    func testMoveNewInFailureRestoresOriginalAndRemovesStaging() throws {
        let files = FailingFiles(failing: .move, onCalls: [2])
        XCTAssertThrowsError(try replace(files)) { XCTAssertEqual($0 as? BundleReplaceError, .swapFailed) }
        XCTAssertEqual(try snapshot(installed), original)
        XCTAssertEqual(try parentContents(), ["Meqat.app"])
        assertStagingRemoved(files)
    }

    func testRollbackFailureKeepsOriginalInStaging() throws {
        let files = FailingFiles(failing: .move, onCalls: [2, 3])
        XCTAssertThrowsError(try replace(files)) { XCTAssertEqual($0 as? BundleReplaceError, .swapFailed) }
        let staging = try XCTUnwrap(files.stagingURL)
        XCTAssertEqual(try snapshot(staging.appendingPathComponent("Meqat-old.app")), original)
        try? FileManager.default.removeItem(at: staging)
    }

    func testCleanupFailureDoesNotThrow() throws {
        let files = FailingFiles(failing: .remove)
        XCTAssertNoThrow(try replace(files))
        XCTAssertEqual(try snapshot(installed), update)
        if let staging = files.stagingURL { try? FileManager.default.removeItem(at: staging) }
    }
}
