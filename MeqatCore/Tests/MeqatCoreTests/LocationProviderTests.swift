import CoreLocation
import XCTest
@testable import MeqatCore

private final class FakeLocationManager: LocationManaging {
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    weak var delegate: CLLocationManagerDelegate?
    var calls: [String] = []
    func requestWhenInUseAuthorization() { calls.append("auth") }
    func requestLocation() { calls.append("request") }
    func startMonitoringSignificantLocationChanges() { calls.append("start") }
    func stopMonitoringSignificantLocationChanges() { calls.append("stop") }
}

/// Records requested durations; each sleep suspends until `fire()` resumes it.
private final class FakeSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var durations: [Duration] = []

    func sleep(_ d: Duration) async throws {
        lock.withLock { durations.append(d) }
        await withCheckedContinuation { c in lock.withLock { waiters.append(c) } }
    }
    func fire() {
        let w = lock.withLock { let w = waiters; waiters = []; return w }
        w.forEach { $0.resume() }
    }
}

private final class Clock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_000_000)
}

@MainActor
final class LocationProviderTests: XCTestCase {
    private var manager: FakeLocationManager!
    private var sleeper: FakeSleeper!
    private var clock: Clock!
    private var provider: LocationProvider!
    private var changes = 0

    override func setUp() {
        manager = FakeLocationManager()
        sleeper = FakeSleeper()
        clock = Clock()
        changes = 0
        let (s, c) = (sleeper!, clock!)
        provider = LocationProvider(manager: manager, now: { c.date }, sleep: { try await s.sleep($0) })
        provider.onChange = { [unowned self] in changes += 1 }
    }

    private func fix(_ lat: Double, _ lon: Double) -> [CLLocation] { [CLLocation(latitude: lat, longitude: lon)] }

    private func startGranted() {
        manager.authorizationStatus = .authorizedAlways
        provider.apply(LocationSettings())
    }

    private func settle() async { for _ in 0..<5 { await Task.yield() } }

    func testNotDeterminedAwaitsPermissionWithoutTimeout() async {
        provider.apply(LocationSettings())
        XCTAssertEqual(provider.state, .awaitingPermission)
        XCTAssertTrue(manager.calls.contains("auth"))
        await settle()
        XCTAssertTrue(sleeper.durations.isEmpty)
    }

    func testDeniedAndRestrictedAreUnavailable() {
        for status in [CLAuthorizationStatus.denied, .restricted] {
            let p = LocationProvider(manager: manager)
            manager.authorizationStatus = status
            p.apply(LocationSettings())
            XCTAssertEqual(p.state, .unavailable)
        }
    }

    func testGrantedWithoutFixAwaitsThenTimesOut() async {
        startGranted()
        XCTAssertEqual(provider.state, .awaitingFix)
        XCTAssertEqual(manager.calls, ["request", "start"])
        await settle()
        XCTAssertEqual(sleeper.durations, [.seconds(10)])
        sleeper.fire()
        await settle()
        XCTAssertEqual(provider.state, .unavailable)
    }

    func testTimeoutDoesNotFireAfterFix() async {
        startGranted()
        await settle()
        provider.handleLocations(fix(23.81034, 90.41))
        sleeper.fire()
        await settle()
        XCTAssertEqual(provider.state, .located(Coordinates(latitude: 23.81, longitude: 90.41)))
    }

    func testFailureBeforeFixIsUnavailable() {
        startGranted()
        provider.handleFailure()
        XCTAssertEqual(provider.state, .unavailable)
    }

    func testPermissionGrantedLaterRestartsFlow() {
        provider.apply(LocationSettings())
        manager.authorizationStatus = .authorizedAlways
        provider.handleAuthorization(.authorizedAlways)
        XCTAssertEqual(provider.state, .awaitingFix)
    }

    func testRevokedWhileLocatedIsUnavailable() {
        startGranted()
        provider.handleLocations(fix(23.81, 90.41))
        provider.handleAuthorization(.denied)
        XCTAssertEqual(provider.state, .unavailable)
        XCTAssertNil(provider.coordinates)
    }

    func testOnChangeFirstFixThenDistance() {
        startGranted()
        provider.handleLocations(fix(23.81, 90.41))
        XCTAssertEqual(changes, 1)
        clock.date += 3 * 3600
        provider.handleLocations(fix(23.819, 90.41))   // ~1 km
        XCTAssertEqual(changes, 1)
        clock.date += 3 * 3600
        provider.handleLocations(fix(23.87, 90.41))    // ~6.6 km from the first
        XCTAssertEqual(changes, 2)
    }

    func testThrottleIgnoresFixWithinTwoHours() {
        startGranted()
        provider.handleLocations(fix(23.81, 90.41))
        clock.date += 3600
        provider.handleLocations(fix(24.5, 90.41))
        XCTAssertEqual(provider.coordinates, Coordinates(latitude: 23.81, longitude: 90.41))
        XCTAssertEqual(changes, 1)
        clock.date += 3601
        provider.handleLocations(fix(24.5, 90.41))
        XCTAssertEqual(changes, 2)
    }

    func testManualDropsCoordinatesAndAutomaticRestarts() {
        startGranted()
        provider.handleLocations(fix(23.81, 90.41))
        provider.apply(LocationSettings(mode: .manual, manualCity: "Dhaka", manualCountry: "BD"))
        XCTAssertEqual(provider.state, .manual(city: "Dhaka", country: "BD", state: nil))
        XCTAssertNil(provider.coordinates)
        XCTAssertEqual(manager.calls.last, "stop")
        manager.calls = []
        provider.apply(LocationSettings())
        XCTAssertEqual(provider.state, .awaitingFix)
        XCTAssertEqual(manager.calls, ["request", "start"])
    }

    func testManualWithEmptyCountryIsUnavailable() {
        provider.apply(LocationSettings(mode: .manual, manualCity: "Dhaka", manualCountry: ""))
        XCTAssertEqual(provider.state, .unavailable)
    }

    func testRounding() {
        startGranted()
        provider.handleLocations(fix(23.81034, 90.41499))
        XCTAssertEqual(provider.coordinates, Coordinates(latitude: 23.81, longitude: 90.41))
    }
}
