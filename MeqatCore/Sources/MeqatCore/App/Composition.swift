import Foundation

/// Glue between the stores and the pure engine, planner and menu types.
public enum Composition {
    /// Yesterday through today + 2, so a window that began last night and the 48 h alert horizon are covered.
    public static func events(cache: TimingsCache?, settings: AppSettings, now: Date, timeZone: TimeZone) -> [ScheduledEvent] {
        guard let cache else { return [] }
        let today = LocalDate(now, timeZone: timeZone)
        return (-1...2).flatMap { EventEngine.events(for: today.adding(days: $0), cache: cache, settings: settings, timeZone: timeZone) ?? [] }
    }

    public static func plan(cache: TimingsCache?, settings: AppSettings, now: Date, timeZone: TimeZone) -> [PlannedAlert] {
        AlertPlanner.plan(events: events(cache: cache, settings: settings, now: now, timeZone: timeZone),
                          settings: settings, now: now, timeZone: timeZone)
    }

    /// nil while there is no location to fetch for.
    public static func fetchParameters(location: LocationState, settings: AppSettings, timeZone: TimeZone) -> FetchParameters? {
        let fetchLocation: FetchLocation
        switch location {
        case .located(let coordinates): fetchLocation = .coordinates(coordinates)
        case .manual(let city, let country, let state): fetchLocation = .city(city: city, country: country, state: state)
        case .awaitingPermission, .awaitingFix, .unavailable: return nil
        }
        return FetchParameters(location: fetchLocation, method: settings.general.method,
                               school: settings.general.school.rawValue, timeZoneId: timeZone.identifier)
    }
}

extension Composition {
    /// A sync that was already running when the mode switched can land with the other mode's location.
    public static func isStale(_ cache: TimingsCache, mode: LocationMode) -> Bool {
        switch (cache.parameters.location, mode) {
        case (.coordinates?, .manual), (.city?, .automatic): true
        default: false
        }
    }
}

extension MenuSyncInfo {
    public init(_ status: SyncStatus) {
        let failure: MenuFailure?
        switch status.lastFailure {
        case .cityNotFound: failure = .cityNotFound
        case .network: failure = .other
        case nil: failure = nil
        }
        self.init(isFetching: status.isFetching, lastSuccess: status.lastSuccess, offlineSince: status.offlineSince, lastFailure: failure)
    }
}

extension MenuLocationInfo {
    public init(_ state: LocationState) {
        switch state {
        case .awaitingPermission: self = .awaitingPermission
        case .awaitingFix: self = .awaitingFix
        case .located, .manual: self = .available
        case .unavailable: self = .missing
        }
    }
}
