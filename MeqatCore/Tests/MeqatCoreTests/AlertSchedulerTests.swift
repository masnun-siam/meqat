import UserNotifications
import XCTest
@testable import MeqatCore

final class FakeNotificationCenter: NotificationCentering, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: UNNotificationRequest] = [:]
    var authorized = true
    var failingIDs: Set<String> = []

    var requests: [UNNotificationRequest] { lock.withLock { store.values.sorted { $0.identifier < $1.identifier } } }

    func add(_ request: UNNotificationRequest) async throws {
        if failingIDs.contains(request.identifier) { throw CocoaError(.fileWriteUnknown) }
        lock.withLock { store[request.identifier] = request }
    }
    func removeAllPendingNotificationRequests() { lock.withLock { store = [:] } }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { requests }
    func isAuthorized() async -> Bool { authorized }
}

final class FakeAlertTimer: AlertTimer {
    private(set) var armed: Date?
    private var handler: (@MainActor () -> Void)?
    private(set) var cancelCount = 0

    func arm(at date: Date, _ handler: @escaping @MainActor () -> Void) { armed = date; self.handler = handler }
    func cancel() { armed = nil; handler = nil; cancelCount += 1 }
    @MainActor func fire() { handler?() }
}

@MainActor
final class AlertSchedulerTests: XCTestCase {
    private let tz = TimeZone(identifier: "Asia/Dhaka")!
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private let center = FakeNotificationCenter()
    private let timer = FakeAlertTimer()

    private func alert(_ id: String, _ offset: TimeInterval, _ style: AlertStyle, _ kind: AlertKind = .start) -> PlannedAlert {
        let date = t0 + offset
        return PlannedAlert(id: id, eventID: .asr, kind: kind, fireDate: date, style: style, title: "Title \(id)",
                            eventInterval: DateInterval(start: date, duration: 600))
    }

    private func make(_ plan: @escaping @MainActor () -> [PlannedAlert]) -> AlertScheduler {
        let clockBox = self
        return AlertScheduler(center: center, timer: timer, now: { [unowned clockBox] in MainActor.assumeIsolated { clockBox.clock } },
                              timeZone: { [tz] in tz }, plan: plan)
    }

    private func rebuild(_ s: AlertScheduler) async {
        s.requestRebuild()
        for _ in 0..<50 { await Task.yield() }
    }

    private func dateParts(_ r: UNNotificationRequest) -> DateComponents { (r.trigger as! UNCalendarNotificationTrigger).dateComponents }

    func testPendingSetEqualsPlanBanners() async {
        let plan = [alert("a", 60, .banner), alert("b", 120, .fullScreen), alert("c", 180, .banner, .preWarning)]
        let s = make { plan }
        await rebuild(s)
        XCTAssertEqual(center.requests.map(\.identifier), ["a", "c"])
        let a = center.requests[0]
        XCTAssertEqual(a.content.title, "Title a")
        XCTAssertEqual(a.content.body, "")
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        XCTAssertEqual(cal.date(from: dateParts(a)), plan[0].fireDate)
        XCTAssertEqual(dateParts(a).second, cal.component(.second, from: plan[0].fireDate))
        XCTAssertEqual(timer.armed, plan[0].fireDate)
    }

    func testReplacingPlanRemovesOldIDs() async {
        var plan = [alert("old", 60, .banner)]
        let s = make { plan }
        await rebuild(s)
        plan = [alert("new", 90, .banner)]
        await rebuild(s)
        XCTAssertEqual(center.requests.map(\.identifier), ["new"])
    }

    func testTenRequestsMergeIntoOneMoreRebuild() async {
        var calls = 0
        var n = 0
        let s = make { calls += 1; return [self.alert("p\(n)", 60, .banner)] }
        for i in 0..<10 { n = i; s.requestRebuild() }
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(center.requests.map(\.identifier), ["p9"])
        XCTAssertLessThanOrEqual(calls, 2)
    }

    func testDisabledEventHasNoRequests() async {
        var settings = AppSettings()
        settings.events[.asr]!.style = .disabled
        let events = [ScheduledEvent(id: .asr, date: LocalDate(year: 2026, month: 10, day: 28),
                                     interval: DateInterval(start: t0 + 3600, duration: 3600), calculatedInterval: nil)]
        let s = make { AlertPlanner.plan(events: events, settings: settings, now: self.t0, timeZone: self.tz) }
        await rebuild(s)
        XCTAssertTrue(center.requests.isEmpty)
        XCTAssertNil(timer.armed)
    }

    func testFullScreenFireWithinToleranceAndDropWhenLate() async {
        var fired: [String] = []
        let s = make { [self.alert("f1", 60, .fullScreen), self.alert("f2", 120, .fullScreen)] }
        s.onFullScreen = { fired.append($0.id) }
        await rebuild(s)
        clock = t0 + 61
        timer.fire()
        XCTAssertEqual(fired, ["f1"])
        XCTAssertEqual(timer.armed, t0 + 120)
        clock = t0 + 126
        timer.fire()
        XCTAssertEqual(fired, ["f1"])
        XCTAssertNil(timer.armed)
    }

    func testLateAlertIsDroppedAndTimerMovesOn() async {
        var fired: [String] = []
        let s = make { [self.alert("f1", 60, .fullScreen), self.alert("f2", 120, .fullScreen)] }
        s.onFullScreen = { fired.append($0.id) }
        await rebuild(s)
        clock = t0 + 66
        timer.fire()
        XCTAssertEqual(fired, [])
        XCTAssertEqual(timer.armed, t0 + 120)
    }

    func testBannerFireCallsOnBannerFired() async {
        var fired: [String] = []
        let s = make { [self.alert("b", 60, .banner)] }
        s.onBannerFired = { fired.append($0.id) }
        await rebuild(s)
        clock = t0 + 60
        timer.fire()
        XCTAssertEqual(fired, ["b"])
    }

    func testSuspendClearsCenterAndTimer() async {
        let s = make { [self.alert("b", 60, .banner)] }
        await rebuild(s)
        s.suspend()
        XCTAssertTrue(center.requests.isEmpty)
        XCTAssertNil(timer.armed)
    }

    func testAuthorizationFollowsCenter() async {
        let s = make { [] }
        await rebuild(s)
        XCTAssertTrue(s.notificationsAuthorized)
        center.authorized = false
        await rebuild(s)
        XCTAssertFalse(s.notificationsAuthorized)
    }

    func testFailedAddDoesNotStopOthers() async {
        center.failingIDs = ["a"]
        let s = make { [self.alert("a", 60, .banner), self.alert("b", 90, .banner)] }
        await rebuild(s)
        XCTAssertEqual(center.requests.map(\.identifier), ["b"])
    }

    func testFajrOffsetChangeMovesEveryFajrStart() async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let cache = try decoder.decode(TimingsCache.self, from: Fixture.data("engine/dhaka-2026-10-28-30.json"))
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 28))!
        var settings = AppSettings()
        let s = make {
            let events = (0...2).flatMap {
                EventEngine.events(for: LocalDate(year: 2026, month: 10, day: 28 + $0), cache: cache, settings: settings, timeZone: self.tz) ?? []
            }
            return AlertPlanner.plan(events: events, settings: settings, now: now, timeZone: self.tz)
        }
        func fajrs() -> [UNNotificationRequest] { center.requests.filter { $0.identifier.hasSuffix("fajr.start") } }

        clock = now
        await rebuild(s)
        let before = fajrs().map { cal.date(from: dateParts($0))! }.sorted()
        XCTAssertEqual(before.count, 2)

        settings.events[.fajr]!.startAlert.offsetMinutes = 10
        await rebuild(s)
        let after = fajrs().map { cal.date(from: dateParts($0))! }.sorted()
        XCTAssertEqual(after, before.map { $0 + 600 })
    }
}
