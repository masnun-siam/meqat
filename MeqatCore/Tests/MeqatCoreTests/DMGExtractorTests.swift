import Darwin
import XCTest

@testable import MeqatCore

/// Records calls; `attach` creates the mount folder, with `Meqat.app` inside when `dmgHasApp`, and a
/// good `ditto` creates its destination.
private final class FakeRunner: CommandRunning, @unchecked Sendable {
    var dmgHasApp = true
    var statuses: [String: Int32] = [:]
    var calls: [(executable: URL, arguments: [String])] = []

    func run(_ executable: URL, _ arguments: [String]) async throws -> Int32 {
        calls.append((executable, arguments))
        let step = executable.lastPathComponent == "ditto" ? "ditto" : arguments[0]
        let status = statuses[step] ?? 0
        if step == "attach", status == 0, let i = arguments.firstIndex(of: "-mountpoint") {
            let mount = URL(fileURLWithPath: arguments[i + 1])
            let folder = dmgHasApp ? mount.appendingPathComponent("Meqat.app") : mount
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        if step == "ditto", status == 0, let destination = arguments.last {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: destination), withIntermediateDirectories: true)
        }
        return status
    }

    var steps: [String] { calls.map { $0.executable.lastPathComponent == "ditto" ? "ditto" : $0.arguments[0] } }
}

final class DMGExtractorTests: XCTestCase {
    private var dir: URL!
    private var dmg: URL!
    private var runner: FakeRunner!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dmg = dir.appendingPathComponent("Meqat-1.8.0.dmg")
        runner = FakeRunner()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func extract() async throws -> URL {
        try await DMGExtractor(runner: runner).extractApp(from: dmg, into: dir)
    }

    private func assertExtract(throws expected: DMGError, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await extract()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? DMGError, expected, file: file, line: line)
        }
    }

    func testHappyPathAttachesCopiesDetaches() async throws {
        let app = try await extract()
        XCTAssertEqual(app.path, dir.appendingPathComponent("Meqat.app").path)
        XCTAssertEqual(runner.steps, ["attach", "ditto", "detach"])

        let attach = runner.calls[0]
        XCTAssertEqual(attach.executable.path, "/usr/bin/hdiutil")
        let mount = attach.arguments[5]
        XCTAssertEqual(URL(fileURLWithPath: mount).deletingLastPathComponent().path, dir.path)
        XCTAssertTrue(URL(fileURLWithPath: mount).lastPathComponent.hasPrefix("mnt-"))
        XCTAssertEqual(
            attach.arguments, ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount, dmg.path])

        XCTAssertEqual(runner.calls[1].executable.path, "/usr/bin/ditto")
        XCTAssertEqual(runner.calls[1].arguments, ["--noqtn", mount + "/Meqat.app", app.path])

        XCTAssertEqual(runner.calls[2].executable.path, "/usr/bin/hdiutil")
        XCTAssertEqual(runner.calls[2].arguments, ["detach", mount, "-force"])
    }

    func testAttachFailureSkipsDetach() async {
        runner.statuses["attach"] = 1
        await assertExtract(throws: .attachFailed)
        XCTAssertEqual(runner.steps, ["attach"])
    }

    func testMissingAppStillDetaches() async {
        runner.dmgHasApp = false
        await assertExtract(throws: .appMissing)
        XCTAssertEqual(runner.steps, ["attach", "detach"])
    }

    func testCopyFailureStillDetaches() async {
        runner.statuses["ditto"] = 1
        await assertExtract(throws: .copyFailed)
        XCTAssertEqual(runner.steps, ["attach", "ditto", "detach"])
    }

    func testDetachFailureStillReturnsApp() async throws {
        runner.statuses["detach"] = 1
        let app = try await extract()
        XCTAssertEqual(app.path, dir.appendingPathComponent("Meqat.app").path)
        XCTAssertEqual(runner.steps, ["attach", "ditto", "detach"])
    }

    /// The PRD's quarantine test: a quarantined app on the mount, copied by the real `ditto`, has no
    /// `com.apple.quarantine` on the bundle or any file in it.
    func testExtractedAppHasNoQuarantine() async throws {
        let realDitto = DittoOnlyRunner(fake: runner, quarantine: Array("0081;00000000;Meqat;".utf8))
        let app = try await DMGExtractor(runner: realDitto).extractApp(from: dmg, into: dir)

        let binary = app.appendingPathComponent("Contents/MacOS/Meqat")
        XCTAssertTrue(FileManager.default.fileExists(atPath: binary.path))
        XCTAssertEqual(getxattr(app.path, "com.apple.quarantine", nil, 0, 0, 0), -1)
        XCTAssertEqual(getxattr(binary.path, "com.apple.quarantine", nil, 0, 0, 0), -1)
    }
}

/// Fakes `hdiutil` and runs the real `ditto`; `attach` puts a quarantined `Meqat.app` on the mount.
private struct DittoOnlyRunner: CommandRunning {
    let fake: FakeRunner
    let quarantine: [UInt8]

    func run(_ executable: URL, _ arguments: [String]) async throws -> Int32 {
        if executable.lastPathComponent == "ditto" {
            return try await ProcessCommandRunner().run(executable, arguments)
        }
        let status = try await fake.run(executable, arguments)
        if arguments[0] == "attach", let i = arguments.firstIndex(of: "-mountpoint") {
            let app = URL(fileURLWithPath: arguments[i + 1]).appendingPathComponent("Meqat.app")
            let binary = app.appendingPathComponent("Contents/MacOS/Meqat")
            try FileManager.default.createDirectory(
                at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("binary".utf8).write(to: binary)
            for path in [app.path, binary.path] {
                guard setxattr(path, "com.apple.quarantine", quarantine, quarantine.count, 0, 0) == 0 else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
        }
        return status
    }
}
