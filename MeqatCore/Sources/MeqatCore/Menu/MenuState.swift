import Foundation

public enum MenuRowMarker: Sendable, Equatable {
    case none, done, current, next, prohibited
}

public struct MenuRow: Sendable, Equatable, Identifiable {
    public let id: EventID
    public let name: String
    public let marker: MenuRowMarker
    public let isDimmed: Bool
    /// `04:52`, `06:05–06:20`, `—` or `23:30 (prev. night)`.
    public let timeText: String
    /// `ends in 1h 11m` or `1h 11m`.
    public let detailText: String?
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
    public let rows: [MenuRow]
    public let emptyState: MenuEmptyState?
    public let showsNotificationsOffRow: Bool
    /// nil unless a newer version is known and the toggle is on.
    public let updateRow: MenuUpdateRow?
    public let footerStatus: String
    public let refreshEnabled: Bool
}
