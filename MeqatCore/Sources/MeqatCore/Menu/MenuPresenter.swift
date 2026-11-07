import Foundation

/// FR-3, FR-13, FR-15 and FR-16, FR-5 of the about-and-updates PRD, and FR-1, FR-2 and FR-7 of the in-app-update PRD: what the status item and dropdown show. No I/O, no clock reads.
public enum MenuPresenter {
    private static let crescent = "☾"

    public static func present(_ input: MenuInput) -> MenuState {
        let f = Formatters(timeZone: input.timeZone, format: input.timeFormat, language: input.language)
        let now = input.now
        let footer = footerStatus(input, f)
        let notificationsOff = !input.notificationsAuthorized
        let updateRow = updateRow(input, f)
        guard input.hasScheduleForToday else {
            let empty = emptyState(input)
            return MenuState(
                statusTitle: crescent, statusAccessibilityLabel: "Meqat", header: nil, hero: nil, rows: [], forbiddenSummary: nil,
                emptyState: empty, emptyMessage: f.t(emptyMessage(empty)),
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
            let (name, cd) = (f.name(prohibited.id), countdown(prohibited.interval!.end.timeIntervalSince(now), f))
            (title, label) = (
                "⛔ " + f.t("%1$@ ends in %2$@", name, cd.short),
                f.t("%1$@, forbidden window, ends in %2$@", name, cd.spoken)
            )
        } else if let banner = input.bannerNow {
            let name = f.name(banner)
            (title, label) = ("● " + f.t("%@ now", name), f.t("%@, now", name))
        } else if let current {
            let (name, cd) = (f.name(current.id), countdown(current.interval!.end.timeIntervalSince(now), f))
            (title, label) = (
                "\(crescent) " + f.t("%1$@ ends in %2$@", name, cd.short),
                f.t("%1$@, current, ends in %2$@", name, cd.spoken)
            )
        } else if let next {
            let (name, cd) = (f.name(next.id), countdown(next.interval!.start.timeIntervalSince(now), f))
            (title, label) = ("\(crescent) " + f.t("%1$@ in %2$@", name, cd.short), f.t("%1$@, next, in %2$@", name, cd.spoken))
        } else {
            (title, label) = (crescent, "Meqat")
        }

        let today = LocalDate(now, timeZone: input.timeZone)
        let header = f.header.string(from: now) + (input.place.map { " · \($0)" } ?? "")
        return MenuState(
            statusTitle: title, statusAccessibilityLabel: label, header: header,
            hero: hero(prohibited: prohibited, current: current, next: next, now, f),
            rows: rows(input, today: today, next: next, f),
            forbiddenSummary: forbiddenSummary(valid, today: today, now, f), emptyState: nil, emptyMessage: nil,
            showsNotificationsOffRow: notificationsOff, updateRow: updateRow, footerStatus: footer, refreshEnabled: !input.sync.isFetching)
    }

    // MARK: Hero and forbidden summary

    /// Follows the status item: a prohibited window wins, then the current event, then the next; `bannerNow` is ignored.
    private static func hero(
        prohibited: ScheduledEvent?, current: ScheduledEvent?, next: ScheduledEvent?, _ now: Date, _ f: Formatters
    ) -> MenuHero? {
        if let e = prohibited ?? current, let iv = e.interval {
            let isForbidden = e == prohibited
            let cd = countdown(iv.end.timeIntervalSince(now), f)
            let nextAt = next.flatMap { n in n.interval.map { (f.name(n.id), f.time.string(from: $0.start)) } }
            let nextText = nextAt.map { "\($0) \($1)" }
            let spokenNext = nextAt.map { f.t(", next %1$@ at %2$@", $0, $1) }
            let name = f.name(e.id)
            return MenuHero(
                kind: isForbidden ? .forbidden : .current, title: isForbidden ? forbiddenTitle(e.id, f) : name,
                countdownText: f.t("%@ left", cd.short), progress: min(1, max(0, now.timeIntervalSince(iv.start) / iv.duration)),
                startText: f.time.string(from: iv.start), nextText: nextText,
                accessibilityLabel:
                    "\(name), \(f.t(isForbidden ? "forbidden window" : "current")), \(f.t("%@ left", cd.spoken))\(spokenNext ?? "")")
        }
        guard let next, let iv = next.interval else { return nil }
        let (name, cd) = (f.name(next.id), countdown(iv.start.timeIntervalSince(now), f))
        let start = f.time.string(from: iv.start)
        return MenuHero(
            kind: .next, title: f.t("Next · %@", name), countdownText: cd.short, progress: nil, startText: start,
            nextText: nil, accessibilityLabel: f.t("Next, %1$@, in %2$@, at %3$@", name, cd.spoken, start))
    }

    private static func forbiddenTitle(_ id: EventID, _ f: Formatters) -> String {
        switch id {
        case .shuruq: f.t("Forbidden · Sunrise")
        case .istiwa: f.t("Forbidden · Noon")
        case .ghurub: f.t("Forbidden · Sunset")
        default: f.name(id)
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
            let none = f.t("No more forbidden windows today")
            return MenuForbiddenSummary(text: none, accessibilityLabel: none)
        }
        let (start, end) = (f.time.string(from: iv.start), f.time.string(from: iv.end))
        return MenuForbiddenSummary(
            text: f.t("Next forbidden %1$@–%2$@", start, end), accessibilityLabel: f.t("Next forbidden window, %1$@ to %2$@", start, end))
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
        let name = f.name(e.id)
        guard let iv = e.interval else {
            return MenuRow(id: e.id, name: name, marker: .none, timeText: "—", accessibilityLabel: f.t("%@, no time today", name))
        }
        let isRange = e.id == .duha
        let start = f.time.string(from: iv.start)
        var timeText = isRange ? "\(start)–\(f.time.string(from: iv.end))" : start
        if e.startsPreviousNight && e.date == today { timeText += f.t(" (prev. night)") }
        let spokenTime = isRange ? f.t("%1$@ to %2$@", start, f.time.string(from: iv.end)) : start

        let marker: MenuRowMarker =
            if iv.end <= now { .done } else if iv.start <= now { .current } else if e == next { .next } else { .none }
        let state: String? =
            switch marker {
            case .done: f.t("done")
            case .current: f.t("current")
            case .next: f.t("next")
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

    private static func emptyMessage(_ state: MenuEmptyState) -> String {
        switch state {
        case .awaitingPermission: "Waiting for location permission…"
        case .fetching: "Fetching times…"
        case .setLocation: "Set your location"
        case .cityNotFound: "City not found — check Location settings"
        case .offline: "No schedule — connect to the internet"
        }
    }

    private static func footerStatus(_ input: MenuInput, _ f: Formatters) -> String {
        let sync = input.sync
        if input.showsCouldntRefresh { return f.t("Couldn't refresh") }
        if sync.isFetching { return f.t("Syncing…") }
        if let since = sync.offlineSince { return f.t("Offline — using cache from %@", f.day.string(from: sync.lastSuccess ?? since)) }
        guard let last = sync.lastSuccess else { return "" }
        if LocalDate(last, timeZone: input.timeZone) == LocalDate(input.now, timeZone: input.timeZone) {
            return f.t("Synced %@", f.time.string(from: last))
        }
        return f.t("Synced %@", "\(f.day.string(from: last)) \(f.time.string(from: last))")
    }

    // MARK: Countdown

    /// Rounded down to whole minutes: `<1m`, `12m`, `1h 0m`.
    private static func countdown(_ interval: TimeInterval, _ f: Formatters) -> (short: String, spoken: String) {
        let total = max(0, Int(interval / 60))
        if total < 1 { return (f.t("<1m"), f.t("less than a minute")) }
        func minutes(_ n: Int) -> String { f.t(n == 1 ? "%d minute" : "%d minutes", n) }
        func hours(_ n: Int) -> String { f.t(n == 1 ? "%d hour" : "%d hours", n) }
        if total < 60 { return (f.t("%dm", total), minutes(total)) }
        let (h, m) = (total / 60, total % 60)
        return (f.t("%1$dh %2$dm", h, m), m == 0 ? hours(h) : "\(hours(h)) \(minutes(m))")
    }

    private static func updateRow(_ input: MenuInput, _ f: Formatters) -> MenuUpdateRow? {
        guard input.checksForUpdates, let notice = input.updateNotice else { return nil }
        switch input.installState {
        case .idle, .failed:
            return MenuUpdateRow(
                title: f.t("Update available — %@", notice.version),
                action: notice.canInstall ? .install : .openRelease(notice.releaseURL))
        case .downloading(let percent):
            return MenuUpdateRow(title: f.t("Downloading update… %d%%", percent), action: nil)
        case .verifying, .installing, .relaunching:
            return MenuUpdateRow(title: f.t("Installing update…"), action: nil)
        }
    }

    /// Dates, text and names in the input's language.
    private struct Formatters {
        let time, header, day: DateFormatter
        let language: Language

        init(timeZone: TimeZone, format: TimeFormat, language: Language) {
            self.language = language
            func make(_ format: String) -> DateFormatter {
                let f = DateFormatter()
                f.locale = language.locale
                f.timeZone = timeZone
                f.dateFormat = format
                return f
            }
            (time, header, day) = (make(format.dateFormat), make("EEE d MMM"), make("d MMM"))
        }

        /// `key` (the English text, a format string) from the `Menu` table, formatted with this language's digits.
        func t(_ key: String, _ args: CVarArg...) -> String {
            String(format: language.localized(key, table: "Menu"), locale: language.locale, arguments: args)
        }

        func name(_ id: EventID) -> String { id.displayName(in: language) }
    }
}
