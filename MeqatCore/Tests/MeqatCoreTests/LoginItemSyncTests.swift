import XCTest
@testable import MeqatCore

private final class FakeLoginItem: LoginItemService {
    struct Failure: Error {}
    var isEnabled: Bool
    var fails = false
    private(set) var registers = 0
    private(set) var unregisters = 0

    init(enabled: Bool) { isEnabled = enabled }

    func register() throws {
        registers += 1
        if fails { throw Failure() }
        isEnabled = true
    }

    func unregister() throws {
        unregisters += 1
        if fails { throw Failure() }
        isEnabled = false
    }
}

final class LoginItemSyncTests: XCTestCase {
    func testRegistersWhenWantedAndNotEnabled() {
        let s = FakeLoginItem(enabled: false)
        XCTAssertNil(LoginItemSync.apply(true, to: s))
        XCTAssertEqual(s.registers, 1)
        XCTAssertTrue(s.isEnabled)
    }

    func testNoCallsWhenAlreadyInState() {
        let on = FakeLoginItem(enabled: true)
        LoginItemSync.apply(true, to: on)
        let off = FakeLoginItem(enabled: false)
        LoginItemSync.apply(false, to: off)
        XCTAssertEqual(on.registers + on.unregisters + off.registers + off.unregisters, 0)
    }

    func testUnregistersWhenNotWantedAndEnabled() {
        let s = FakeLoginItem(enabled: true)
        XCTAssertNil(LoginItemSync.apply(false, to: s))
        XCTAssertEqual(s.unregisters, 1)
        XCTAssertFalse(s.isEnabled)
    }

    func testRegisterErrorIsReturned() {
        let s = FakeLoginItem(enabled: false)
        s.fails = true
        XCTAssertNotNil(LoginItemSync.apply(true, to: s))
        XCTAssertFalse(s.isEnabled)
    }

    func testUnregisterErrorIsReturned() {
        let s = FakeLoginItem(enabled: true)
        s.fails = true
        XCTAssertNotNil(LoginItemSync.apply(false, to: s))
        XCTAssertTrue(s.isEnabled)
    }

    func testLaunchAtLoginDefaultsOn() {
        XCTAssertTrue(GeneralSettings().launchAtLogin)
    }
}
