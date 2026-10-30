import XCTest
@testable import MeqatCore

private final class Clock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_000_000)
}

@MainActor
final class UpdateSchedulerTests: XCTestCase {
    private var sleeper: ManualSleeper!
    private var clock: Clock!
    private var scheduler: UpdateScheduler!
    private var calls = 0

    override func setUp() {
        sleeper = ManualSleeper()
        clock = Clock()
        calls = 0
        let (s, c) = (sleeper!, clock!)
        scheduler = UpdateScheduler(
            check: { [unowned self] in calls += 1 },
            now: { c.date },
            sleep: { await s.sleep($0) }
        )
    }

    override func tearDown() {
        scheduler.stop()
    }

    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    private func advance(_ duration: Duration) async {
        clock.date.addTimeInterval(Double(duration.components.seconds))
        await sleeper.advance(by: duration)
        await settle()
    }

    func testFirstCallAfterLaunchDelayThenEvery24Hours() async {
        scheduler.start(after: UpdateScheduler.launchDelay)
        await settle()
        await advance(.seconds(9))
        XCTAssertEqual(calls, 0)
        await advance(.seconds(1))
        XCTAssertEqual(calls, 1)
        await advance(.seconds(86400))
        XCTAssertEqual(calls, 2)
        let requested = await sleeper.requestedDurations
        XCTAssertEqual(requested.prefix(2), [.seconds(10), .seconds(86400)])
    }

    func testStartWithZeroDelayCallsAtOnce() async {
        scheduler.start(after: .zero)
        await settle()
        await advance(.zero)
        XCTAssertEqual(calls, 1)
    }

    func testStopPreventsFurtherCalls() async {
        scheduler.start(after: .seconds(10))
        await settle()
        scheduler.stop()
        await advance(.seconds(86400 * 3))
        XCTAssertEqual(calls, 0)
    }

    func testWakeWhenOverdueCallsOnceAndSchedulesNext24HoursLater() async {
        scheduler.start(after: .zero)
        await settle()
        await advance(.zero)
        XCTAssertEqual(calls, 1)
        clock.date.addTimeInterval(86400 * 3)
        scheduler.wake()
        await settle()
        await advance(.zero)
        XCTAssertEqual(calls, 2)
        await advance(.seconds(86399))
        XCTAssertEqual(calls, 2)
        await advance(.seconds(1))
        XCTAssertEqual(calls, 3)
    }

    func testWakeBeforeDueDoesNothing() async {
        scheduler.start(after: .zero)
        await settle()
        await advance(.zero)
        clock.date.addTimeInterval(3600)
        scheduler.wake()
        await settle()
        await advance(.zero)
        XCTAssertEqual(calls, 1)
    }

    func testWakeWhileStoppedDoesNothing() async {
        scheduler.start(after: .zero)
        await settle()
        await advance(.zero)
        scheduler.stop()
        clock.date.addTimeInterval(86400 * 3)
        scheduler.wake()
        await settle()
        await advance(.zero)
        XCTAssertEqual(calls, 1)
    }

    func testStartAgainReplacesRunningSchedule() async {
        scheduler.start(after: .seconds(10))
        await settle()
        scheduler.start(after: .seconds(10))
        await settle()
        await advance(.seconds(10))
        XCTAssertEqual(calls, 1)
        await advance(.seconds(86400))
        XCTAssertEqual(calls, 2)
    }
}
