import Foundation

public struct LocalDate: Comparable, Hashable, Sendable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    public static func < (a: LocalDate, b: LocalDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var utcNoon: Date {
        Self.utcCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    public func adding(days: Int) -> LocalDate {
        let shifted = Self.utcCalendar.date(byAdding: .day, value: days, to: utcNoon)!
        return LocalDate(shifted, timeZone: Self.utcCalendar.timeZone)
    }

    public func startOfDay(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Gregorian weekday, 1 = Sunday ... 6 = Friday ... 7 = Saturday.
    public var weekday: Int {
        Self.utcCalendar.component(.weekday, from: utcNoon)
    }

    public var yearMonth: YearMonth { YearMonth(year: year, month: month) }

    // MARK: Codable as "yyyy-MM-dd"

    public init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
            (1...12).contains(m), (1...31).contains(d)
        else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date \(string)"))
        }
        self.init(year: y, month: m, day: d)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "%04d-%02d-%02d", year, month, day))
    }
}

public struct YearMonth: Comparable, Hashable, Sendable, Codable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public static func < (a: YearMonth, b: YearMonth) -> Bool {
        (a.year, a.month) < (b.year, b.month)
    }
}
