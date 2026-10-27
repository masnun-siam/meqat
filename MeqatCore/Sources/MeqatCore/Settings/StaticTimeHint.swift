import Foundation

public enum StaticTimeHint {
    /// True when `time`, on the date `window` starts, falls outside `window` (edges count as inside).
    public static func isOutside(_ time: ClockTime, window: DateInterval, timeZone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let resolved = calendar.date(
            bySettingHour: time.hour, minute: time.minute, second: 0,
            of: calendar.startOfDay(for: window.start), matchingPolicy: .nextTime)
        else { return false }
        return !window.contains(resolved)
    }
}
