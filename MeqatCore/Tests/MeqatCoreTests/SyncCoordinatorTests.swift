import XCTest
@testable import MeqatCore

@MainActor
final class SyncCoordinatorTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let dhaka = Coordinates(latitude: 23.8103, longitude: 90.4125)
    private let oct15 = Date(timeIntervalSince1970: 1_792_065_600) // 2026-10-15 12:00 UTC
    private let jan30 = Date(timeIntervalSince1970: 1_801_396_800) // 2027-01-30 12:00 UTC

    private var directory: URL!
    private var store: CacheStore!
    private var stub: StubAladhan!
    private var sleeper: ManualSleeper!
    private var current: FetchParameters?
    private var now: Date!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = CacheStore(directory: directory)
        stub = StubAladhan()
        sleeper = ManualSleeper()
        now = oct15
        current = params()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var fileURL: URL { directory.appendingPathComponent("timings.json") }

    private func params(method: Int? = 2, tz: String = "UTC") -> FetchParameters {
        FetchParameters(location: .coordinates(dhaka), method: method, school: 0, timeZoneId: tz)
    }

    private func makeCoordinator() -> SyncCoordinator {
        let date = now!
        let sleeper = sleeper!
        return SyncCoordinator(
            client: stub, store: store, parameters: { [unowned self] in current },
            now: { date }, timeZone: { [utc] in utc }, sleep: { await sleeper.sleep($0) })
    }

    private func savedCache(_ p: FetchParameters, today: LocalDate = LocalDate(year: 2026, month: 10, day: 15)) throws -> TimingsCache {
        let dates = (-1...30).map { today.adding(days: $0) }
        let cache = TimingsCache(parameters: p, fetchedAt: Date(timeIntervalSince1970: 0),
                                 days: Dictionary(uniqueKeysWithValues: dates.map { ($0, StubAladhan.day($0)) }))
        try store.save(cache)
        return cache
    }

    private func eventually(_ message: String = "", file: StaticString = #filePath, line: UInt = #line,
                            _ condition: () async -> Bool) async {
        for _ in 0..<1000 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("timed out \(message)", file: file, line: line)
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(100)) }

    private func failOffline() async { await stub.fail(with: URLError(.notConnectedToInternet)) }

    // MARK: Triggers

    func testPeriodicWithFreshMatchingCacheMakesNoRequests() async throws {
        _ = try savedCache(params())
        let coordinator = makeCoordinator()
        coordinator.trigger(.periodic)
        await settle()
        let count = await stub.calls.count
        XCTAssertEqual(count, 0)
        XCTAssertFalse(coordinator.status.isFetching)
    }

    func testTimeZoneChangeMakesExactlyOneSync() async throws {
        _ = try savedCache(params(tz: "Asia/Dhaka"))
        let coordinator = makeCoordinator()
        coordinator.trigger(.timeZoneChanged)
        await eventually { coordinator.cache?.parameters.timeZoneId == "UTC" && !coordinator.status.isFetching }
        let count = await stub.calls.count
        XCTAssertEqual(count, 2)
    }

    func testNoLocationDoesNothing() async {
        current = nil
        let coordinator = makeCoordinator()
        coordinator.trigger(.refreshNow)
        coordinator.trigger(.periodic)
        await settle()
        let count = await stub.calls.count
        XCTAssertEqual(count, 0)
        XCTAssertFalse(coordinator.status.isFetching)
    }

    func testThreeRefreshNowWhileInFlightMakeOneSync() async {
        await stub.hold()
        let coordinator = makeCoordinator()
        (0..<3).forEach { _ in coordinator.trigger(.refreshNow) }
        await eventually { await self.stub.calls.count == 1 }
        XCTAssertTrue(coordinator.status.isFetching)
        await stub.release()
        await eventually { !coordinator.status.isFetching }
        let count = await stub.calls.count
        XCTAssertEqual(count, 2)
    }

    func testThreeRefreshNowOn30JanMakeThreeRequests() async {
        now = jan30
        await stub.hold()
        let coordinator = makeCoordinator()
        (0..<3).forEach { _ in coordinator.trigger(.refreshNow) }
        await eventually { await self.stub.calls.count == 1 }
        await stub.release()
        await eventually { !coordinator.status.isFetching }
        let months = await stub.calls.map(\.month)
        XCTAssertEqual(months, [YearMonth(year: 2027, month: 1), YearMonth(year: 2027, month: 2), YearMonth(year: 2027, month: 3)])
    }

    func testSettingsChangeDuringSyncQueuesOneFollowUp() async {
        current = params(method: 2)
        await stub.hold()
        let coordinator = makeCoordinator()
        coordinator.trigger(.refreshNow)
        await eventually { await self.stub.calls.count == 1 }
        current = params(method: 3)
        coordinator.trigger(.locationChanged)
        coordinator.trigger(.locationChanged)
        await stub.release()
        await eventually { coordinator.cache?.parameters.method == 3 && !coordinator.status.isFetching }
        let methods = await stub.calls.map(\.parameters.method)
        XCTAssertEqual(methods, [2, 2, 3, 3])
    }

    func testFiveSettingsChangesMakeOneSyncOneSecondAfterTheLast() async {
        let coordinator = makeCoordinator()
        for i in 0..<5 {
            coordinator.trigger(.settingsChanged)
            if i < 4 { await sleeper.advance(by: .milliseconds(200)) }
        }
        await settle()
        var count = await stub.calls.count
        XCTAssertEqual(count, 0)
        await sleeper.advance(by: .milliseconds(999))
        await settle()
        count = await stub.calls.count
        XCTAssertEqual(count, 0, "first debounce deadlines passed, the last one has not")
        await sleeper.advance(by: .milliseconds(1))
        await eventually { await self.stub.calls.count == 2 }
        await settle()
        count = await stub.calls.count
        XCTAssertEqual(count, 2)
    }

    // MARK: Failure and backoff

    func testFiveAttemptsWithBackoffAndCacheUntouched() async throws {
        let original = try savedCache(params(method: 1))
        let bytes = try Data(contentsOf: fileURL)
        await failOffline()
        let coordinator = makeCoordinator()
        coordinator.trigger(.refreshNow)

        for waits in 1...4 {
            await eventually { await self.sleeper.requestedDurations.count == waits && !coordinator.status.isFetching }
            XCTAssertTrue(coordinator.status.isWaitingToRetry)
            XCTAssertEqual(coordinator.status.offlineSince, oct15)
            await sleeper.advance(by: .seconds(300))
        }
        await eventually { await self.stub.calls.count == 5 && !coordinator.status.isFetching }
        await settle()

        let durations = await sleeper.requestedDurations
        XCTAssertEqual(durations, [.seconds(15), .seconds(30), .seconds(60), .seconds(300)])
        XCTAssertFalse(coordinator.status.isWaitingToRetry)
        XCTAssertEqual(coordinator.status.lastFailure, .network)
        XCTAssertEqual(try Data(contentsOf: fileURL), bytes)
        XCTAssertEqual(coordinator.cache, original)
    }

    func testTriggerDuringBackoffSyncsAtOnceAndRestartsSequence() async {
        await failOffline()
        let coordinator = makeCoordinator()
        coordinator.trigger(.refreshNow)
        await eventually { await self.sleeper.requestedDurations.count == 1 }
        await sleeper.advance(by: .seconds(15))
        await eventually { await self.sleeper.requestedDurations.count == 2 }
        var count = await stub.calls.count
        XCTAssertEqual(count, 2)

        coordinator.trigger(.periodic)
        await settle()
        count = await stub.calls.count
        XCTAssertEqual(count, 2, "periodic tick during a wait is ignored")
        XCTAssertTrue(coordinator.status.isWaitingToRetry)

        coordinator.trigger(.refreshNow)
        await eventually { await self.sleeper.requestedDurations.count == 3 }
        count = await stub.calls.count
        XCTAssertEqual(count, 3)
        let durations = await sleeper.requestedDurations
        XCTAssertEqual(durations, [.seconds(15), .seconds(30), .seconds(15)])

        await sleeper.advance(by: .seconds(30))
        await settle()
        count = await stub.calls.count
        XCTAssertEqual(count, 4, "only the new wait fires; the cancelled 30 s wait does not")
    }

    func testCityNotFoundSchedulesNoRetry() async {
        await stub.fail(with: AladhanError.cityNotFound)
        let coordinator = makeCoordinator()
        coordinator.trigger(.refreshNow)
        await eventually { coordinator.status.lastFailure == .cityNotFound && !coordinator.status.isFetching }
        await settle()
        let durations = await sleeper.requestedDurations
        XCTAssertTrue(durations.isEmpty)
        XCTAssertFalse(coordinator.status.isWaitingToRetry)
        XCTAssertNil(coordinator.status.offlineSince)
    }

    // MARK: Success

    func testSuccessWritesFetchedDaysAndClearsFailure() async throws {
        await failOffline()
        let coordinator = makeCoordinator()
        coordinator.trigger(.refreshNow)
        await eventually { await self.sleeper.requestedDurations.count == 1 }
        XCTAssertNotNil(coordinator.status.offlineSince)
        await stub.fail(with: nil)
        var replaced: TimingsCache?
        coordinator.onCacheReplaced = { replaced = $0 }
        await sleeper.advance(by: .seconds(15))
        await eventually { coordinator.cache != nil && !coordinator.status.isFetching }

        let saved = try XCTUnwrap(store.load())
        XCTAssertEqual(saved.days.count, 61)
        XCTAssertEqual(saved.parameters, params())
        XCTAssertEqual(saved.fetchedAt, oct15)
        XCTAssertEqual(coordinator.cache, saved)
        XCTAssertEqual(replaced, saved)
        XCTAssertEqual(coordinator.status.lastSuccess, oct15)
        XCTAssertNil(coordinator.status.offlineSince)
        XCTAssertNil(coordinator.status.lastFailure)
        XCTAssertFalse(coordinator.status.isWaitingToRetry)
    }

    func testClearCachedLocationSavesAndPublishesStrippedCache() throws {
        let original = try savedCache(params())
        let coordinator = makeCoordinator()
        var replaced: TimingsCache?
        coordinator.onCacheReplaced = { replaced = $0 }
        coordinator.clearCachedLocation()
        let stripped = original.strippingLocation()
        XCTAssertEqual(coordinator.cache, stripped)
        XCTAssertEqual(replaced, stripped)
        XCTAssertEqual(store.load(), stripped)
    }
}
