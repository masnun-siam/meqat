import CoreLocation
import Foundation
import Observation

public enum LocationState: Equatable, Sendable {
    case awaitingPermission
    case awaitingFix
    case located(Coordinates)
    case manual(city: String, country: String, state: String?)
    case unavailable
}

/// The subset of `CLLocationManager` the provider uses, so tests can fake it.
public protocol LocationManaging: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var delegate: CLLocationManagerDelegate? { get set }
    func requestWhenInUseAuthorization()
    func requestLocation()
    func startMonitoringSignificantLocationChanges()
    func stopMonitoringSignificantLocationChanges()
}

extension CLLocationManager: LocationManaging {}

@MainActor @Observable
public final class LocationProvider: NSObject, CLLocationManagerDelegate {
    static let fixTimeout: Duration = .seconds(10)
    static let minUpdateInterval: TimeInterval = 2 * 60 * 60
    static let reportDistance: CLLocationDistance = 5_000

    public private(set) var state: LocationState = .unavailable
    /// The current rounded fix; nil outside automatic mode or while no fix exists.
    public private(set) var coordinates: Coordinates?
    @ObservationIgnored public var onChange: (() -> Void)?

    @ObservationIgnored private let manager: LocationManaging
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var mode: LocationMode?
    @ObservationIgnored private var fixTimer: Task<Void, Never>?
    @ObservationIgnored private var lastAccepted: Date?
    @ObservationIgnored private var lastReported: Coordinates?

    public init(
        manager: LocationManaging = CLLocationManager(),
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.manager = manager
        self.now = now
        self.sleep = sleep
        super.init()
        manager.delegate = self
    }

    /// Call at launch and whenever location settings change.
    public func apply(_ location: LocationSettings) {
        switch location.mode {
        case .manual:
            stopAutomatic()
            if let city = location.manualCity, !city.isEmpty,
                let country = location.manualCountry, !country.isEmpty
            {
                state = .manual(city: city, country: country, state: location.manualState)
            } else {
                state = .unavailable
            }
            mode = .manual
        case .automatic:
            guard mode != .automatic else { return }
            mode = .automatic
            handleAuthorization(manager.authorizationStatus)
        }
    }

    // MARK: Automatic flow

    func handleAuthorization(_ status: CLAuthorizationStatus) {
        guard mode == .automatic else { return }
        switch status {
        case .authorizedAlways, .authorizedWhenInUse, .authorized:
            switch state {
            case .awaitingFix, .located: return
            default: beginFix()
            }
        case .notDetermined:
            guard state != .awaitingPermission else { return }
            stopAutomatic()
            state = .awaitingPermission
            manager.requestWhenInUseAuthorization()
        default:
            stopAutomatic()
            state = .unavailable
        }
    }

    func handleLocations(_ locations: [CLLocation]) {
        guard mode == .automatic, let fix = locations.last else { return }
        let date = now()
        if let last = lastAccepted, date.timeIntervalSince(last) < Self.minUpdateInterval { return }
        lastAccepted = date
        fixTimer?.cancel()
        let rounded = Coordinates(
            latitude: Self.round2(fix.coordinate.latitude),
            longitude: Self.round2(fix.coordinate.longitude))
        coordinates = rounded
        state = .located(rounded)
        if let last = lastReported {
            let moved = CLLocation(latitude: rounded.latitude, longitude: rounded.longitude)
                .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
            guard moved > Self.reportDistance else { return }
        }
        lastReported = rounded
        onChange?()
    }

    func handleFailure() {
        guard mode == .automatic, state == .awaitingFix else { return }
        fixTimer?.cancel()
        state = .unavailable  // monitoring stays on, so a late fix still recovers
    }

    private func beginFix() {
        state = .awaitingFix
        manager.requestLocation()
        manager.startMonitoringSignificantLocationChanges()
        fixTimer?.cancel()
        fixTimer = Task { [sleep] in
            do { try await sleep(Self.fixTimeout) } catch { return }
            if state == .awaitingFix {
                state = .unavailable
            }
        }
    }

    /// Stops CoreLocation and forgets every in-memory fix.
    private func stopAutomatic() {
        manager.stopMonitoringSignificantLocationChanges()
        fixTimer?.cancel()
        fixTimer = nil
        coordinates = nil
        lastAccepted = nil
        lastReported = nil
    }

    private static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    // MARK: CLLocationManagerDelegate

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in handleAuthorization(status) }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in handleLocations(locations) }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in handleFailure() }
    }
}
