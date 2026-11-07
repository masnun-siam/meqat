import XCTest

@testable import MeqatCore

final class InstallEligibilityTests: XCTestCase {
    private var dir: URL!
    private var bundle: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        bundle = dir.appendingPathComponent("Meqat.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }

    private let allGood = InstallFacts(parentWritable: true, volumeReadOnly: false, translocated: false, sandboxed: false)

    func testCanInstallOnlyWhenEveryFactAllows() {
        XCTAssertTrue(InstallEligibility.canInstall(allGood))
        var facts = allGood
        facts.parentWritable = false
        XCTAssertFalse(InstallEligibility.canInstall(facts))
        facts = allGood
        facts.volumeReadOnly = true
        XCTAssertFalse(InstallEligibility.canInstall(facts))
        facts = allGood
        facts.translocated = true
        XCTAssertFalse(InstallEligibility.canInstall(facts))
        facts = allGood
        facts.sandboxed = true
        XCTAssertFalse(InstallEligibility.canInstall(facts))
    }

    func testProbeOnWritableTempBundle() {
        let facts = InstallEligibility.probe(bundleURL: bundle, environment: [:])
        XCTAssertTrue(facts.parentWritable)
        XCTAssertFalse(facts.volumeReadOnly)
        XCTAssertFalse(facts.translocated)
    }

    func testProbeWithReadOnlyParent() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        XCTAssertFalse(InstallEligibility.probe(bundleURL: bundle, environment: [:]).parentWritable)
    }

    func testProbeOnTranslocatedPath() {
        let url = URL(fileURLWithPath: "/private/var/folders/xx/T/AppTranslocation/ABC/d/Meqat.app")
        XCTAssertTrue(InstallEligibility.probe(bundleURL: url, environment: [:]).translocated)
    }

    func testProbeReadsSandboxFromEnvironment() {
        XCTAssertTrue(InstallEligibility.probe(bundleURL: bundle, environment: ["APP_SANDBOX_CONTAINER_ID": "x"]).sandboxed)
        XCTAssertFalse(InstallEligibility.probe(bundleURL: bundle, environment: [:]).sandboxed)
    }

    func testUnreadableVolumeCountsAsReadOnly() {
        let missing = dir.appendingPathComponent("missing/Meqat.app")
        XCTAssertTrue(InstallEligibility.probe(bundleURL: missing, environment: [:]).volumeReadOnly)
    }
}
