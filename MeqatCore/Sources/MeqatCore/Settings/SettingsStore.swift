import Foundation
import Observation

private struct Envelope<Value: Codable>: Codable {
    var version: Int
    var value: Value
}

@MainActor @Observable
public final class SettingsStore {
    private static let version = 1
    private static let generalKey = "settings.general"
    private static let locationKey = "settings.location"
    private static let eventsKey = "settings.events"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored public var onChange: ((_ old: AppSettings, _ new: AppSettings) -> Void)?

    public var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            if settings.general != oldValue.general { save(settings.general, key: Self.generalKey) }
            if settings.location != oldValue.location { save(settings.location, key: Self.locationKey) }
            if settings.events != oldValue.events { save(EventsGroup(settings.events), key: Self.eventsKey) }
            onChange?(oldValue, settings)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = AppSettings(
            general: Self.load(GeneralSettings.self, key: Self.generalKey, from: defaults) ?? .init(),
            location: Self.load(LocationSettings.self, key: Self.locationKey, from: defaults) ?? .init(),
            events: Self.load(EventsGroup.self, key: Self.eventsKey, from: defaults)?.events ?? AppSettings.defaultEvents)
    }

    public func resetEvent(_ id: EventID) {
        settings.events[id] = .defaults(for: id)
    }

    /// Restores General and every event; the location stays.
    public func resetAll() {
        settings = AppSettings(location: settings.location)
    }

    public func setLocationMode(_ mode: LocationMode) {
        settings.location = mode == .automatic ? LocationSettings() : LocationSettings(mode: .manual, manualCity: settings.location.manualCity, manualCountry: settings.location.manualCountry, manualState: settings.location.manualState)
    }

    public func setManualLocation(city: String, country: String, state: String?) {
        settings.location = LocationSettings(mode: .manual, manualCity: city, manualCountry: country, manualState: state)
    }

    private func save<Value: Codable>(_ value: Value, key: String) {
        defaults.set(try? JSONEncoder().encode(Envelope(version: Self.version, value: value)), forKey: key)
    }

    private static func load<Value: Codable>(_ type: Value.Type, key: String, from defaults: UserDefaults) -> Value? {
        guard let data = defaults.data(forKey: key),
              let envelope = try? JSONDecoder().decode(Envelope<Value>.self, from: data),
              envelope.version == version else { return nil }
        return envelope.value
    }
}
