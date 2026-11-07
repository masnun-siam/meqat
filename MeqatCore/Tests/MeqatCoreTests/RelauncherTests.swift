import XCTest

@testable import MeqatCore

private final class RecordingLauncher: ProcessLaunching, @unchecked Sendable {
    private(set) var launches: [(executable: URL, arguments: [String])] = []
    var failure: Error?

    func launch(_ executable: URL, _ arguments: [String]) throws {
        launches.append((executable, arguments))
        if let failure { throw failure }
    }
}

private struct LaunchFailed: Error, Equatable {}

final class RelauncherTests: XCTestCase {
    func testLaunchesShellOnceWithPidAndPath() throws {
        let fake = RecordingLauncher()
        let app = URL(fileURLWithPath: "/Applications/Meqat.app")
        try Relauncher.relaunch(app, pid: 4242, launcher: fake)
        XCTAssertEqual(fake.launches.count, 1)
        XCTAssertEqual(fake.launches.first?.executable.path, "/bin/sh")
        XCTAssertEqual(fake.launches.first?.arguments, ["-c", Relauncher.script, "sh", "4242", app.path])
    }

    func testPathWithSpacesAndQuotesIsOneUnsplicedArgument() throws {
        let fake = RecordingLauncher()
        let app = URL(fileURLWithPath: "/tmp/a b'c/Meqat.app")
        try Relauncher.relaunch(app, pid: 1, launcher: fake)
        let arguments = try XCTUnwrap(fake.launches.first?.arguments)
        XCTAssertEqual(arguments.last, "/tmp/a b'c/Meqat.app")
        XCTAssertEqual(arguments[1], Relauncher.script)
        XCTAssertFalse(Relauncher.script.contains("a b'c"))
    }

    func testRethrowsLauncherError() {
        let fake = RecordingLauncher()
        fake.failure = LaunchFailed()
        XCTAssertThrowsError(try Relauncher.relaunch(URL(fileURLWithPath: "/x.app"), pid: 1, launcher: fake)) {
            XCTAssertEqual($0 as? LaunchFailed, LaunchFailed())
        }
    }

    func testProcessLauncherStartsRealProcess() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("relauncher-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try ProcessLauncher().launch(
            URL(fileURLWithPath: "/bin/sh"), ["-c", "echo ok > \"$1\"", "sh", file.path])
        XCTAssertTrue(appears(file))
    }

    // `open` swapped for `touch`: proves the real script quotes the path and skips the wait for an exited pid.
    func testScriptHandsQuotedPathToOpenAfterExit() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("a b'c-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let script = Relauncher.script.replacingOccurrences(of: "/usr/bin/open", with: "/usr/bin/touch")
        var arguments = Relauncher.arguments(app: file, pid: Int32.max)
        arguments[1] = script
        try ProcessLauncher().launch(URL(fileURLWithPath: "/bin/sh"), arguments)
        XCTAssertTrue(appears(file))
    }

    private func appears(_ file: URL) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: file.path) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        return FileManager.default.fileExists(atPath: file.path)
    }
}
