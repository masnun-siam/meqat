import Foundation

public enum AlertKind: String, Sendable {
    case start, end, preWarning
}

public struct PlannedAlert: Equatable, Sendable {
    /// `<yyyy-MM-dd list date>.<eventID>.<kind>`, for example `2026-10-28.asr.start`.
    public let id: String
    public let eventID: EventID
    public let kind: AlertKind
    public let fireDate: Date
    /// Only `.banner` or `.fullScreen`.
    public let style: AlertStyle
    public let title: String
    public let eventInterval: DateInterval
}

public enum AlertPlanner {
    public static let horizon: TimeInterval = 48 * 3600
    public static let maxBanners = 60

    public static func plan(events: [ScheduledEvent], settings: AppSettings, now: Date, timeZone: TimeZone) -> [PlannedAlert] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = settings.general.timeFormat.dateFormat

        let all = events.flatMap { alerts(for: $0, settings[event: $0.id], formatter) }
            .filter { now < $0.fireDate && $0.fireDate <= now + horizon }
            .sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }

        var banners = 0
        return all.filter {
            guard $0.style == .banner else { return true }
            banners += 1
            return banners <= maxBanners
        }
    }

    private static func alerts(for event: ScheduledEvent, _ s: EventSettings, _ formatter: DateFormatter) -> [PlannedAlert] {
        guard s.style != .disabled, let interval = event.interval else { return [] }
        let name = event.id.displayName
        let prohibited = event.id.kind == .prohibited
        let start = formatter.string(from: interval.start)
        let end = formatter.string(from: interval.end)
        let day = String(format: "%04d-%02d-%02d", event.date.year, event.date.month, event.date.day)

        func make(_ kind: AlertKind, _ fire: Date, _ style: AlertStyle, _ title: String) -> PlannedAlert {
            PlannedAlert(
                id: "\(day).\(event.id.rawValue).\(kind.rawValue)", eventID: event.id, kind: kind,
                fireDate: fire, style: style, title: title, eventInterval: interval)
        }

        var out: [PlannedAlert] = []
        if s.startAlert.enabled {
            out.append(
                make(
                    .start, interval.start + TimeInterval(s.startAlert.offsetMinutes * 60), s.style,
                    prohibited ? "⛔ \(name) · avoid praying until \(end)" : "\(name) · \(start)"))
        }
        if s.endAlert.enabled {
            let lead = s.endAlert.leadMinutes
            out.append(make(.end, interval.end - TimeInterval(lead * 60), s.style, "\(name) ends in \(lead) min"))
        }
        if s.preWarning.enabled {
            let lead = s.preWarning.leadMinutes
            out.append(
                make(
                    .preWarning, interval.start - TimeInterval(lead * 60), .banner,
                    "\(prohibited ? "⛔ " : "")\(name) in \(lead) min"))
        }
        return out
    }
}
