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

    /// Shown under the event on a full-screen overlay; `nil` for start alerts.
    public var overlayLine: String? { kind == .start ? nil : title }
}

public enum AlertPlanner {
    public static let horizon: TimeInterval = 48 * 3600
    public static let maxBanners = 60

    public static func plan(
        events: [ScheduledEvent], settings: AppSettings, now: Date, timeZone: TimeZone, language: Language = .english
    ) -> [PlannedAlert] {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.timeZone = timeZone
        formatter.dateFormat = settings.general.timeFormat.dateFormat

        let all = events.flatMap { alerts(for: $0, settings[event: $0.id], formatter, language) }
            .filter { now < $0.fireDate && $0.fireDate <= now + horizon }
            .sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }

        var banners = 0
        return all.filter {
            guard $0.style == .banner else { return true }
            banners += 1
            return banners <= maxBanners
        }
    }

    private static func alerts(
        for event: ScheduledEvent, _ s: EventSettings, _ formatter: DateFormatter, _ language: Language
    ) -> [PlannedAlert] {
        guard let interval = event.interval else { return [] }
        let name = event.id.displayName(in: language)
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
                    .start, interval.start + TimeInterval(s.startAlert.offsetMinutes * 60), s.startAlert.style,
                    prohibited
                        ? "⛔ " + title("%1$@ · avoid praying until %2$@", language, name, end)
                        : title("%1$@ · %2$@", language, name, start)))
        }
        if s.endAlert.enabled {
            let lead = s.endAlert.leadMinutes
            out.append(
                make(
                    .end, interval.end - TimeInterval(lead * 60), s.endAlert.style,
                    title("%1$@ ends in %2$d min", language, name, lead)))
        }
        if s.preWarning.enabled {
            let lead = s.preWarning.leadMinutes
            out.append(
                make(
                    .preWarning, interval.start - TimeInterval(lead * 60), s.preWarning.style,
                    (prohibited ? "⛔ " : "") + title("%1$@ in %2$d min", language, name, lead)))
        }
        return out
    }

    /// `key` is the English format string and the key in `bn.lproj/Alerts.strings`; the locale gives Bangla digits.
    private static func title(_ key: String, _ language: Language, _ args: CVarArg...) -> String {
        String(format: language.localized(key, table: "Alerts"), locale: language.locale, arguments: args)
    }
}
