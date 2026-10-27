import XCTest
@testable import MeqatCore

final class OverlayHoldTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testCountsDownWhileResumed() {
        var hold = OverlayHold(seconds: 60)
        hold.resume(at: t0)
        XCTAssertEqual(hold.remaining(at: t0), 60)
        XCTAssertFalse(hold.isSatisfied(at: t0.addingTimeInterval(59)))
        XCTAssertEqual(hold.remaining(at: t0.addingTimeInterval(60)), 0)
        XCTAssertTrue(hold.isSatisfied(at: t0.addingTimeInterval(60)))
    }

    func testPausedTimeDoesNotCount() {
        var hold = OverlayHold(seconds: 60)
        hold.resume(at: t0)
        hold.pause(at: t0.addingTimeInterval(20))
        hold.resume(at: t0.addingTimeInterval(100))
        XCTAssertEqual(hold.remaining(at: t0.addingTimeInterval(100)), 40)
    }

    func testZeroHoldIsSatisfiedAtOnce() {
        let hold = OverlayHold(seconds: 0)
        XCTAssertTrue(hold.isSatisfied(at: t0))
    }

    func testPausingTwiceIsHarmless() {
        var hold = OverlayHold(seconds: 60)
        hold.resume(at: t0)
        hold.pause(at: t0.addingTimeInterval(10))
        hold.pause(at: t0.addingTimeInterval(30))
        XCTAssertEqual(hold.remaining(at: t0.addingTimeInterval(30)), 50)
    }

    func testResumingTwiceKeepsFirstStart() {
        var hold = OverlayHold(seconds: 60)
        hold.resume(at: t0)
        hold.resume(at: t0.addingTimeInterval(30))
        XCTAssertEqual(hold.remaining(at: t0.addingTimeInterval(30)), 30)
    }
}
