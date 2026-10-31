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
                statusTitle: crescent, statusAccessibilityLabel: "Meqat", header: nil, hero: nil, rows: [], forbiddenSummary: nil,
                emptyState: emptyState(input),
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
            hero: hero(prohibited: prohibited, current: current, next: next, now, f),
            rows: rows(input, today: today, next: next, f),
            forbiddenSummary: forbiddenSummary(valid, today: today, now, f), emptyState: nil,
            showsNotificationsOffRow: notificationsOff, updateRow: updateRow, footerStatus: footer, refreshEnabled: !input.sync.isFetching)
    }

    // MARK: Hero and forbidden summary

    /// Follows the status item: a prohibited window wins, then the current event, then the next; `bannerNow` is ignored.
    private static func hero(
        prohibited: ScheduledEvent?, current: ScheduledEvent?, next: ScheduledEvent?, _ now: Date, _ f: Formatters
    ) -> MenuHero? {
        if let e = prohibited ?? current, let iv = e.interval {
            let isForbidden = e == prohibited
            let cd = countdown(iv.end.timeIntervalSince(now))
            let nextText = next.flatMap { n in n.interval.map { "\(n.id.displayName) \(f.time.string(from: $0.start))" } }
            let spokenNext = next.flatMap { n in n.interval.map { ", next \(n.id.displayName) at \(f.time.string(from: $0.start))" } }
            let name = e.id.displayName
            return MenuHero(
                kind: isForbidden ? .forbidden : .current, title: isForbidden ? forbiddenTitle(e.id) : name,
                countdownText: "\(cd.short) left", progress: min(1, max(0, now.timeIntervalSince(iv.start) / iv.duration)),
                startText: f.time.string(from: iv.start), nextText: nextText,
                accessibilityLabel: "\(name), \(isForbidden ? "forbidden window" : "current"), \(cd.spoken) left\(spokenNext ?? "")")
        }
        guard let next, let iv = next.interval else { return nil }
        let cd = countdown(iv.start.timeIntervalSince(now))
        let start = f.time.string(from: iv.start)
        return MenuHero(
            kind: .next, title: "Next · \(next.id.displayName)", countdownText: cd.short, progress: nil, startText: start,
            nextText: nil, accessibilityLabel: "Next, \(next.id.displayName), in \(cd.spoken), at \(start)")
    }

    private static func forbiddenTitle(_ id: EventID) -> String {
        switch id {
        case .shuruq: "Forbidden · Sunrise"
        case .istiwa: "Forbidden · Noon"
        case .ghurub: "Forbidden · Sunset"
        default: id.displayName
        }
    }

    /// The date's next prohibited window still to start, whatever its style.
    private static func forbiddenSummary(_ valid: [ScheduledEvent], today: LocalDate, _ now: Date, _ f: Formatters)
        -> MenuForbiddenSummary
    {
        guard
            let iv = valid.filter({ $0.id.kind == .prohibited && $0.date == today && $0.interval!.start > now })
                .map({ $0.interval! }).min(by: { $0.start < $1.start })
        else {
            let none = "No more forbidden windows today"
            return MenuForbiddenSummary(text: none, accessibilityLabel: none)
        }
        let (start, end) = (f.time.string(from: iv.start), f.time.string(from: iv.end))
        return MenuForbiddenSummary(text: "Next forbidden \(start)–\(end)", accessibilityLabel: "Next forbidden window, \(start) to \(end)")
    }

    // MARK: Rows

    private static func rows(_ input: MenuInput, today: LocalDate, next: ScheduledEvent?, _ f: Formatters) -> [MenuRow] {
        var list = input.events.filter { $0.date == today && $0.id.kind != .prohibited }
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
        guard let iv = e.interval else {
            return MenuRow(id: e.id, name: name, marker: .none, timeText: "—", accessibilityLabel: "\(name), no time today")
        }
        let isRange = e.id == .duha
        let start = f.time.string(from: iv.start)
        var timeText = isRange ? "\(start)–\(f.time.string(from: iv.end))" : start
        if e.startsPreviousNight && e.date == today { timeText += " (prev. night)" }
        let spokenTime = isRange ? "\(start) to \(f.time.string(from: iv.end))" : start

        let marker: MenuRowMarker =
            if iv.end <= now { .done } else if iv.start <= now { .current } else if e == next { .next } else { .none }
        let state: String? =
            switch marker {
            case .done: "done"
            case .current: "current"
            case .next: "next"
            case .none: nil
            }
        return MenuRow(
            id: e.id, name: name, marker: marker, timeText: timeText,
            accessibilityLabel: [name, state, spokenTime].compactMap { $0 }.joined(separator: ", "))
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
