import Foundation

public enum MenuRowMarker: Sendable, Equatable {
    case none, done, current, next
}

public struct MenuRow: Sendable, Equatable, Identifiable {
    public let id: EventID
    public let name: String
    public let marker: MenuRowMarker
    /// `04:52`, `06:20–11:36` (Duha), `—` or `23:30 (prev. night)`.
    public let timeText: String
    public let accessibilityLabel: String
}

public enum MenuHeroKind: Sendable, Equatable {
    case current, forbidden, next
}

/// The dropdown's top block: the status item's event and how long is left.
public struct MenuHero: Sendable, Equatable {
    public let kind: MenuHeroKind
    /// Mixed case (`Dhuhr`, `Forbidden · Noon`, `Next · Asr`); the view uppercases it.
    public let title: String
    /// `1h 6m left`, or `4m` for `.next`.
    public let countdownText: String
    /// 0…1 through the event; nil for `.next`.
    public let progress: Double?
    /// The event's start time.
    public let startText: String
    /// `Isha 18:42`; nil for `.next` or when there is no next event.
    public let nextText: String?
    public let accessibilityLabel: String
}

/// `Next forbidden 17:12–17:27` or `No more forbidden windows today`.
public struct MenuForbiddenSummary: Sendable, Equatable {
    public let text: String
    public let accessibilityLabel: String
}

public enum MenuEmptyAction: Sendable, Equatable {
    case openLocationPane, tryAgain
}

public enum MenuEmptyState: Sendable, Equatable {
    case awaitingPermission, fetching, setLocation, cityNotFound, offline

    public var message: String {
        switch self {
        case .awaitingPermission: "Waiting for location permission…"
        case .fetching: "Fetching times…"
        case .setLocation: "Set your location"
        case .cityNotFound: "City not found — check Location settings"
        case .offline: "No schedule — connect to the internet"
        }
    }

    public var action: MenuEmptyAction? {
        switch self {
        case .awaitingPermission, .setLocation, .cityNotFound: .openLocationPane
        case .offline: .tryAgain
        case .fetching: nil
        }
    }
}

public struct MenuUpdateRow: Sendable, Equatable {
    public let title: String
    public let url: URL
}

public struct MenuState: Sendable, Equatable {
    public let statusTitle: String
    public let statusAccessibilityLabel: String
    /// `Wed 28 Oct · Dhaka`; nil without today's schedule.
    public let header: String?
    /// nil without a current or next event, or without today's schedule.
    public let hero: MenuHero?
    public let rows: [MenuRow]
    /// nil without today's schedule.
    public let forbiddenSummary: MenuForbiddenSummary?
    public let emptyState: MenuEmptyState?
    public let showsNotificationsOffRow: Bool
    /// nil unless a newer version is known and the toggle is on.
    public let updateRow: MenuUpdateRow?
    public let footerStatus: String
    public let refreshEnabled: Bool
}
