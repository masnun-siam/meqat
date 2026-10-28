import Foundation

public struct Coordinates: Equatable, Sendable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum FetchLocation: Equatable, Sendable {
    case coordinates(Coordinates)
    case city(city: String, country: String, state: String?)
}

public struct FetchParameters: Equatable, Sendable {
    /// nil means "stripped" (location fields cleared on a mode switch).
    public var location: FetchLocation?
    /// nil = Aladhan default.
    public var method: Int?
    /// 0 or 1.
    public var school: Int
    public var timeZoneId: String

    public init(location: FetchLocation?, method: Int?, school: Int, timeZoneId: String) {
        self.location = location
        self.method = method
        self.school = school
        self.timeZoneId = timeZoneId
    }
}

public struct DayTimings: Equatable, Sendable, Codable {
    public var date: LocalDate
    public var fajr, sunrise, dhuhr, asr, sunset, maghrib, isha, midnight, lastthird: Date

    public init(
        date: LocalDate, fajr: Date, sunrise: Date, dhuhr: Date, asr: Date, sunset: Date,
        maghrib: Date, isha: Date, midnight: Date, lastthird: Date
    ) {
        self.date = date
        self.fajr = fajr
        self.sunrise = sunrise
        self.dhuhr = dhuhr
        self.asr = asr
        self.sunset = sunset
        self.maghrib = maghrib
        self.isha = isha
        self.midnight = midnight
        self.lastthird = lastthird
    }
}

public struct TimingsCache: Equatable, Sendable, Codable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var parameters: FetchParameters
    public var fetchedAt: Date
    public var days: [LocalDate: DayTimings]

    public init(
        formatVersion: Int = TimingsCache.currentFormatVersion, parameters: FetchParameters,
        fetchedAt: Date, days: [LocalDate: DayTimings]
    ) {
        self.formatVersion = formatVersion
        self.parameters = parameters
        self.fetchedAt = fetchedAt
        self.days = days
    }

    public func day(_ date: LocalDate) -> DayTimings? { days[date] }

    /// True only when every date from `from` through `through` has an entry.
    public func covers(from: LocalDate, through: LocalDate) -> Bool {
        var date = from
        while date <= through {
            if days[date] == nil { return false }
            date = date.adding(days: 1)
        }
        return true
    }

    public func strippingLocation() -> TimingsCache {
        var copy = self
        copy.parameters.location = nil
        return copy
    }

    // MARK: Codable (flat keys, null when unused, days sorted by date)

    private enum CodingKeys: String, CodingKey {
        case formatVersion, timeZoneId, latitude, longitude, city, country, state, method, school, fetchedAt, days
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        fetchedAt = try c.decode(Date.self, forKey: .fetchedAt)

        let latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        let longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        let city = try c.decodeIfPresent(String.self, forKey: .city)
        let country = try c.decodeIfPresent(String.self, forKey: .country)
        let location: FetchLocation?
        if let latitude, let longitude {
            location = .coordinates(Coordinates(latitude: latitude, longitude: longitude))
        } else if let city, let country {
            location = .city(city: city, country: country, state: try c.decodeIfPresent(String.self, forKey: .state))
        } else {
            location = nil
        }
        parameters = FetchParameters(
            location: location,
            method: try c.decodeIfPresent(Int.self, forKey: .method),
            school: try c.decode(Int.self, forKey: .school),
            timeZoneId: try c.decode(String.self, forKey: .timeZoneId))

        let list = try c.decode([DayTimings].self, forKey: .days)
        days = Dictionary(list.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(formatVersion, forKey: .formatVersion)
        try c.encode(parameters.timeZoneId, forKey: .timeZoneId)

        var latitude: Double?
        var longitude: Double?
        var city: String?
        var country: String?
        var state: String?
        switch parameters.location {
        case .coordinates(let coordinates):
            latitude = coordinates.latitude
            longitude = coordinates.longitude
        case .city(let c, let co, let s):
            city = c
            country = co
            state = s
        case nil:
            break
        }
        // encode(_: T?) writes explicit nulls, as the PRD's layout shows.
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encode(city, forKey: .city)
        try c.encode(country, forKey: .country)
        try c.encode(state, forKey: .state)
        try c.encode(parameters.method, forKey: .method)
        try c.encode(parameters.school, forKey: .school)
        try c.encode(fetchedAt, forKey: .fetchedAt)
        try c.encode(days.values.sorted { $0.date < $1.date }, forKey: .days)
    }
}
