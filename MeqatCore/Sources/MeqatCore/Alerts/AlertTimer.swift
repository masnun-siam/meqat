import Foundation

public protocol AlertTimer: AnyObject {
    func arm(at date: Date, _ handler: @escaping @MainActor () -> Void)
    func cancel()
}

/// One exact wall-clock timer. `.strict` keeps it out of timer coalescing without exempting the app from App Nap.
public final class DispatchAlertTimer: AlertTimer {
    private var source: DispatchSourceTimer?

    public init() {}

    public func arm(at date: Date, _ handler: @escaping @MainActor () -> Void) {
        cancel()
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        let wall = DispatchWallTime(timespec: timespec(tv_sec: Int(date.timeIntervalSince1970),
                                                       tv_nsec: Int((date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)) * 1e9)))
        timer.schedule(wallDeadline: wall, leeway: .milliseconds(50))
        timer.setEventHandler { MainActor.assumeIsolated { handler() } }
        source = timer
        timer.resume()
    }

    public func cancel() {
        source?.cancel()
        source = nil
    }
}
