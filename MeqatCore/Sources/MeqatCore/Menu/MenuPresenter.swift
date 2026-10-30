import Foundation

/// FR-3, FR-13, FR-15 and FR-16, and FR-5 of the about-and-updates PRD: what the status item and dropdown show. No I/O, no clock reads.
public enum MenuPresenter {
    private static let crescent = "☾"

    public static func present(_ input: MenuInput) -> MenuState {
        let f = Formatters(timeZone: input.timeZone, format: input.timeFormat)
        let now = input.now
        let footer = footerStatus(input, f)
        let notificationsOff = !input.notificationsAuthorized
        let updateRow =
            input.checksForUpdates
            ? input.updateNotice.map { MenuUpdateRow(title: "Update available — \($0.version)", url: $0.releaseURL) } : nil
        guard input.hasScheduleForToday else {
            return MenuState(
                statusTitle: crescent, statusAccessibilityLabel: "Meqat", header: nil, rows: [], emptyState: emptyState(input),
                showsNotificationsOffRow: notificationsOff, updateRow: updateRow, footerStatus: footer,
                refreshEnabled: !input.sync.isFetching)
        }

        let valid = input.events.filter { $0.interval != nil }
        let prohibited = valid.first { $0.id.kind == .prohibited && $0.interval!.contains(now) && now < $0.interval!.end }
        let current =
            valid
            .filter { $0.interval!.start <= now && now < $0.interval!.end && input.styles[$0.id] != .disabled }
            .max { $0.interval!.start < $1.interval!.start }
        let next =
            valid
            .filter { $0.interval!.start > now && input.styles[$0.id] != .disabled }
            .min { $0.interval!.start < $1.interval!.start }

        let (title, label): (String, String)
        if let prohibited {
            let cd = countdown(prohibited.interval!.end.timeIntervalSince(now))
            (title, label) = (
                "⛔ \(prohibited.id.displayName) ends in \(cd.short)",
                "\(prohibited.id.displayName), forbidden window, ends in \(cd.spoken)"
            )
        } else if let banner = input.bannerNow {
            (title, label) = ("● \(banner.displayName) now", "\(banner.displayName), now")
        } else if let current {
            let cd = countdown(current.interval!.end.timeIntervalSince(now))
            (title, label) = (
                "\(crescent) \(current.id.displayName) ends in \(cd.short)",
                "\(current.id.displayName), current, ends in \(cd.spoken)"
            )
        } else if let next {
            let cd = countdown(next.interval!.start.timeIntervalSince(now))
            (title, label) = ("\(crescent) \(next.id.displayName) in \(cd.short)", "\(next.id.displayName), next, in \(cd.spoken)")
        } else {
            (title, label) = (crescent, "Meqat")
        }

        let today = LocalDate(now, timeZone: input.timeZone)
        let header = f.header.string(from: now) + (input.place.map { " · \($0)" } ?? "")
        return MenuState(
            statusTitle: title, statusAccessibilityLabel: label, header: header,
            rows: rows(input, today: today, next: next, f), emptyState: nil,
            showsNotificationsOffRow: notificationsOff, updateRow: updateRow, footerStatus: footer, refreshEnabled: !input.sync.isFetching)
    }

    // MARK: Rows

    private static func rows(_ input: MenuInput, today: LocalDate, next: ScheduledEvent?, _ f: Formatters) -> [MenuRow] {
        var list = input.events.filter { $0.date == today }
        // A Static Tahajjud that started last night is current in today's list from its start.
        if let carried = input.events.first(where: {
            $0.id == .tahajjud && $0.date == today.adding(days: 1) && $0.startsPreviousNight
                && ($0.interval.map { input.now >= $0.start } ?? false)
        }), let i = list.firstIndex(where: { $0.id == .tahajjud }) {
            list[i] = carried
        }
        return list.map { row($0, today: today, next: next, input.now, f) }
    }

    private static func row(_ e: ScheduledEvent, today: LocalDate, next: ScheduledEvent?, _ now: Date, _ f: Formatters) -> MenuRow {
        let name = e.id.displayName
        let prohibited = e.id.kind == .prohibited
        guard let iv = e.interval else {
            return MenuRow(
                id: e.id, name: name, marker: prohibited ? .prohibited : .none, isDimmed: false, timeText: "—", detailText: nil,
                accessibilityLabel: "\(name), no time today")
        }
        let isRange = prohibited || e.id == .duha
        let start = f.time.string(from: iv.start)
        let range = "\(start)–\(f.time.string(from: iv.end))"
        var timeText = isRange ? range : start
        if e.startsPreviousNight && e.date == today { timeText += " (prev. night)" }
        let spokenTime = isRange ? "\(start) to \(f.time.string(from: iv.end))" : start

        var marker = MenuRowMarker.none
        var detail: String?
        var label = "\(name), \(spokenTime)"
        if iv.end <= now {
            marker = prohibited ? .prohibited : .done
            label = "\(name), done, \(spokenTime)"
        } else if iv.start <= now {
            marker = .current
            let cd = countdown(iv.end.timeIntervalSince(now))
            detail = "ends in \(cd.short)"
            label = "\(name), current, \(spokenTime), ends in \(cd.spoken)"
        } else if e == next {
            marker = .next
            let cd = countdown(iv.start.timeIntervalSince(now))
            detail = cd.short
            label = "\(name), next, \(spokenTime), in \(cd.spoken)"
        } else if prohibited {
            marker = .prohibited
        }
        if prohibited { label = "\(name), forbidden window, \(spokenTime)" }
        return MenuRow(
            id: e.id, name: name, marker: marker, isDimmed: prohibited && iv.end <= now, timeText: timeText, detailText: detail,
            accessibilityLabel: label)
    }

    // MARK: Empty state and footer

    private static func emptyState(_ input: MenuInput) -> MenuEmptyState {
        if input.location == .awaitingPermission { return .awaitingPermission }
        if input.sync.isFetching || input.location == .awaitingFix { return .fetching }
        if input.location == .missing { return .setLocation }
        switch input.sync.lastFailure {
        case .cityNotFound: return .cityNotFound
        case .other: return .offline
        case nil: return .fetching  // location is available and the first sync hasn't started
        }
    }

    private static func footerStatus(_ input: MenuInput, _ f: Formatters) -> String {
        let sync = input.sync
        if input.showsCouldntRefresh { return "Couldn't refresh" }
        if sync.isFetching { return "Syncing…" }
        if let since = sync.offlineSince { return "Offline — using cache from \(f.day.string(from: sync.lastSuccess ?? since))" }
        guard let last = sync.lastSuccess else { return "" }
        if LocalDate(last, timeZone: input.timeZone) == LocalDate(input.now, timeZone: input.timeZone) {
            return "Synced \(f.time.string(from: last))"
        }
        return "Synced \(f.day.string(from: last)) \(f.time.string(from: last))"
    }

    // MARK: Countdown

    /// Rounded down to whole minutes: `<1m`, `12m`, `1h 0m`.
    private static func countdown(_ interval: TimeInterval) -> (short: String, spoken: String) {
        let total = max(0, Int(interval / 60))
        if total < 1 { return ("<1m", "less than a minute") }
        func plural(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }
        if total < 60 { return ("\(total)m", plural(total, "minute")) }
        let (h, m) = (total / 60, total % 60)
        return ("\(h)h \(m)m", m == 0 ? plural(h, "hour") : "\(plural(h, "hour")) \(plural(m, "minute"))")
    }

    private struct Formatters {
        let time, header, day: DateFormatter

        init(timeZone: TimeZone, format: TimeFormat) {
            func make(_ format: String) -> DateFormatter {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = timeZone
                f.dateFormat = format
                return f
            }
            (time, header, day) = (make(format.dateFormat), make("EEE d MMM"), make("d MMM"))
        }
    }
}
