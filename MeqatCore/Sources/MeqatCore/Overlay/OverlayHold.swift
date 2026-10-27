import Foundation

/// Counts down an overlay's minimum hold, only while the overlay is visible.
public struct OverlayHold: Equatable {
    public let seconds: Int
    private var elapsed: TimeInterval = 0
    private var resumedAt: Date?

    public init(seconds: Int) {
        self.seconds = max(0, seconds)
    }

    public mutating func resume(at date: Date) {
        if resumedAt == nil { resumedAt = date }
    }

    public mutating func pause(at date: Date) {
        guard let start = resumedAt else { return }
        elapsed += max(0, date.timeIntervalSince(start))
        resumedAt = nil
    }

    public func remaining(at date: Date) -> TimeInterval {
        var used = elapsed
        if let start = resumedAt { used += max(0, date.timeIntervalSince(start)) }
        return max(0, TimeInterval(seconds) - used)
    }

    public func isSatisfied(at date: Date) -> Bool {
        remaining(at: date) <= 0
    }
}
