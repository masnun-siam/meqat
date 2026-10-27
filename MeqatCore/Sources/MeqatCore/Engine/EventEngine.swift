import Foundation

/// FR-1, FR-2 and FR-10: a day's 10 events as absolute instants. No I/O, no clock reads.
public enum EventEngine {
    public static func events(for date: LocalDate, cache: TimingsCache, settings: AppSettings, timeZone: TimeZone) -> [ScheduledEvent]? {
        guard let day = cache.day(date) else { return nil }
        return events(for: date, day: day, previousDay: cache.day(date.adding(days: -1)), settings: settings, timeZone: timeZone)
    }

    public static func events(for date: LocalDate, day: DayTimings, previousDay: DayTimings?, settings: AppSettings, timeZone: TimeZone) -> [ScheduledEvent] {
        let calendar = gregorian(timeZone)
        let general = settings.general
        func minutes(_ n: Int) -> TimeInterval { TimeInterval(n * 60) }
        func staticStart(_ id: EventID, on date: LocalDate) -> Date? {
            let s = settings[event: id]
            guard s.timeSource == .fixed, let time = s.staticTime else { return nil }
            return resolve(time, on: date, calendar: calendar)
        }

        // Prohibited windows: Static sets the start and the window keeps its duration.
        func prohibited(_ id: EventID, calculatedStart: Date, calculatedEnd: Date, duration: Int) -> (start: Date, end: Date) {
            guard let start = staticStart(id, on: date) else { return (calculatedStart, calculatedEnd) }
            return (start, start.addingTimeInterval(minutes(duration)))
        }
        // Other events: Static moves the start only.
        func span(_ id: EventID, calculatedStart: Date, end: Date) -> (start: Date, end: Date) {
            (staticStart(id, on: date) ?? calculatedStart, end)
        }

        let calcShuruqEnd = day.sunrise.addingTimeInterval(minutes(general.shuruqMinutes))
        let calcIstiwaStart = day.dhuhr.addingTimeInterval(-minutes(general.istiwaMinutes))
        let calcGhurubStart = day.sunset.addingTimeInterval(-minutes(general.ghurubMinutes))

        let shuruq = prohibited(.shuruq, calculatedStart: day.sunrise, calculatedEnd: calcShuruqEnd, duration: general.shuruqMinutes)
        let istiwa = prohibited(.istiwa, calculatedStart: calcIstiwaStart, calculatedEnd: day.dhuhr, duration: general.istiwaMinutes)
        let ghurub = prohibited(.ghurub, calculatedStart: calcGhurubStart, calculatedEnd: day.sunset, duration: general.ghurubMinutes)
        let isFriday = date.weekday == 6
        let midday: EventID = isFriday ? .jumah : .dhuhr

        func event(_ id: EventID, _ effective: (start: Date, end: Date)?, calculated: (start: Date, end: Date)?, startsPreviousNight: Bool = false) -> ScheduledEvent {
            ScheduledEvent(id: id, date: date, interval: effective.flatMap(window), calculatedInterval: calculated.flatMap(window), startsPreviousNight: startsPreviousNight)
        }
        func simple(_ id: EventID, start: Date, end: Date) -> ScheduledEvent {
            event(id, span(id, calculatedStart: start, end: end), calculated: (start, end))
        }

        let tahajjud = tahajjudEvent(for: date, day: day, previousDay: previousDay, settings: settings[event: .tahajjud], calendar: calendar)
        return [
            tahajjud,
            simple(.fajr, start: day.fajr, end: day.sunrise),
            event(.shuruq, shuruq, calculated: (day.sunrise, calcShuruqEnd)),
            event(.duha, (shuruq.end, istiwa.start), calculated: (calcShuruqEnd, calcIstiwaStart)),
            event(.istiwa, istiwa, calculated: (calcIstiwaStart, day.dhuhr)),
            simple(midday, start: day.dhuhr, end: day.asr),
            simple(.asr, start: day.asr, end: day.sunset),
            event(.ghurub, ghurub, calculated: (calcGhurubStart, day.sunset)),
            simple(.maghrib, start: day.maghrib, end: day.isha),
            simple(.isha, start: day.isha, end: day.midnight),
        ]
    }

    private static func tahajjudEvent(for date: LocalDate, day: DayTimings, previousDay: DayTimings?, settings: EventSettings, calendar: Calendar) -> ScheduledEvent {
        guard let previousDay else { return ScheduledEvent(id: .tahajjud, date: date, interval: nil, calculatedInterval: nil) }
        let calculated = interval(start: previousDay.lastthird, end: day.fajr)
        guard settings.timeSource == .fixed, let time = settings.staticTime else {
            return ScheduledEvent(id: .tahajjud, date: date, interval: calculated, calculatedInterval: calculated)
        }
        let ishaParts = calendar.dateComponents([.hour, .minute], from: previousDay.isha)
        let previousNight = (time.hour, time.minute) >= (ishaParts.hour!, ishaParts.minute!)
        let start = resolve(time, on: previousNight ? date.adding(days: -1) : date, calendar: calendar)
        return ScheduledEvent(id: .tahajjud, date: date, interval: interval(start: start, end: day.fajr), calculatedInterval: calculated, startsPreviousNight: previousNight)
    }

    /// `DateInterval` traps when end < start, and an empty window is "—" too.
    private static func interval(start: Date, end: Date) -> DateInterval? {
        end > start ? DateInterval(start: start, end: end) : nil
    }

    private static func window(_ w: (start: Date, end: Date)) -> DateInterval? { interval(start: w.start, end: w.end) }

    private static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// `.nextTime` moves a minute skipped by a DST change to the next valid one.
    private static func resolve(_ time: ClockTime, on date: LocalDate, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: date.startOfDay(in: calendar.timeZone), matchingPolicy: .nextTime)!
    }
}
