import Foundation

public enum MenuFailure: Sendable, Equatable {
    case cityNotFound, other
}

public struct MenuSyncInfo: Sendable, Equatable {
    public var isFetching: Bool
    public var lastSuccess: Date?
    public var offlineSince: Date?
    public var lastFailure: MenuFailure?

    public init(isFetching: Bool = false, lastSuccess: Date? = nil, offlineSince: Date? = nil, lastFailure: MenuFailure? = nil) {
        self.isFetching = isFetching
        self.lastSuccess = lastSuccess
        self.offlineSince = offlineSince
        self.lastFailure = lastFailure
    }
}

public enum MenuLocationInfo: Sendable, Equatable {
    case awaitingPermission, awaitingFix, missing, available
}

/// Everything the status item and dropdown depend on (FR-15, FR-16). No clock reads.
public struct MenuInput: Sendable, Equatable {
    public var now: Date
    public var timeZone: TimeZone
    /// Engine output for any of yesterday, today, tomorrow and the day after. Missing dates aren't searched.
    public var events: [ScheduledEvent]
    public var styles: [EventID: AlertStyle]
    public var place: String?
    public var hasScheduleForToday: Bool
    public var sync: MenuSyncInfo
    public var location: MenuLocationInfo
    public var notificationsAuthorized: Bool
    public var bannerNow: EventID?
    public var showsCouldntRefresh: Bool
    public var timeFormat: TimeFormat

    public init(
        now: Date, timeZone: TimeZone, events: [ScheduledEvent], styles: [EventID: AlertStyle] = [:], place: String? = nil,
        hasScheduleForToday: Bool = true, sync: MenuSyncInfo = MenuSyncInfo(), location: MenuLocationInfo = .available,
        notificationsAuthorized: Bool = true, bannerNow: EventID? = nil, showsCouldntRefresh: Bool = false,
        timeFormat: TimeFormat = .twentyFour
    ) {
        self.now = now
        self.timeZone = timeZone
        self.events = events
        self.styles = styles
        self.place = place
        self.hasScheduleForToday = hasScheduleForToday
        self.sync = sync
        self.location = location
        self.notificationsAuthorized = notificationsAuthorized
        self.bannerNow = bannerNow
        self.showsCouldntRefresh = showsCouldntRefresh
        self.timeFormat = timeFormat
    }
}
