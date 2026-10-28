import Foundation

public struct ScheduledEvent: Equatable, Sendable {
    public let id: EventID
    /// The list date this event belongs to.
    public let date: LocalDate
    /// nil = shown as "—", with no alerts.
    public let interval: DateInterval?
    /// The window with every time source set to calculated.
    public let calculatedInterval: DateInterval?
    /// True only for a Static Tahajjud placed on the previous date.
    public let startsPreviousNight: Bool

    public init(id: EventID, date: LocalDate, interval: DateInterval?, calculatedInterval: DateInterval?, startsPreviousNight: Bool = false)
    {
        self.id = id
        self.date = date
        self.interval = interval
        self.calculatedInterval = calculatedInterval
        self.startsPreviousNight = startsPreviousNight
    }
}
