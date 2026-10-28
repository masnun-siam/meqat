import CoreLocation
import Foundation

extension FetchParameters {
    /// nil when the location settings are incomplete (no coordinates in automatic mode, no city or country in manual mode).
    public static func current(general: GeneralSettings, location: LocationSettings, coordinates: Coordinates?, timeZone: TimeZone)
        -> FetchParameters?
    {
        let fetchLocation: FetchLocation
        switch location.mode {
        case .automatic:
            guard let coordinates else { return nil }
            fetchLocation = .coordinates(coordinates)
        case .manual:
            guard let city = location.manualCity, !city.isEmpty,
                let country = location.manualCountry, !country.isEmpty
            else { return nil }
            let state = location.manualState.flatMap { $0.isEmpty ? nil : $0 }
            fetchLocation = .city(city: city, country: country, state: state)
        }
        return FetchParameters(
            location: fetchLocation, method: general.method, school: general.school.rawValue, timeZoneId: timeZone.identifier)
    }
}

public enum SyncPolicy {
    public static let moveThresholdMeters: Double = 5_000

    public static func needsFetch(cache: TimingsCache?, current: FetchParameters, today: LocalDate) -> Bool {
        guard let cache else { return true }
        let p = cache.parameters
        return !cache.covers(from: today.adding(days: -1), through: today.adding(days: 30))
            || locationsDiffer(p.location, current.location)
            || p.method != current.method
            || p.school != current.school
            || p.timeZoneId != current.timeZoneId
    }

    /// Every month from yesterday through today + 30 days, in order.
    public static func months(today: LocalDate) -> [YearMonth] {
        let last = today.adding(days: 30).yearMonth
        var month = today.adding(days: -1).yearMonth
        var result = [month]
        while month < last {
            month = month.month == 12 ? YearMonth(year: month.year + 1, month: 1) : YearMonth(year: month.year, month: month.month + 1)
            result.append(month)
        }
        return result
    }

    private static func locationsDiffer(_ a: FetchLocation?, _ b: FetchLocation?) -> Bool {
        switch (a, b) {
        case (.coordinates(let x)?, .coordinates(let y)?):
            return CLLocation(latitude: x.latitude, longitude: x.longitude)
                .distance(from: CLLocation(latitude: y.latitude, longitude: y.longitude)) > moveThresholdMeters
        case (.city(let c1, let k1, let s1)?, .city(let c2, let k2, let s2)?):
            return c1 != c2 || k1 != k2 || s1 != s2
        default:
            return true
        }
    }
}
