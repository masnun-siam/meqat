import Foundation

/// Runs the automatic update check shortly after start, then every 24 hours of wall time.
@MainActor
public final class UpdateScheduler {
    public static let launchDelay: Duration = .seconds(10)
    static let interval: TimeInterval = 24 * 3600

    private let check: @MainActor () -> Void
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void

    private var loopTask: Task<Void, Never>?
    private var nextDue: Date?

    public init(
        check: @escaping @MainActor () -> Void,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.check = check
        self.now = now
        self.sleep = sleep
    }

    /// Replaces any running schedule: first check after `delay`, then every 24 hours.
    public func start(after delay: Duration) {
        loopTask?.cancel()
        loopTask = Task { [sleep] in
            try? await sleep(delay)
            while !Task.isCancelled {
                // Set before checking so a wake right after the timer fired does not double-fire.
                nextDue = now().addingTimeInterval(Self.interval)
                check()
                try? await sleep(.seconds(Self.interval))
            }
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
        nextDue = nil
    }

    /// Runs one overdue check after the Mac wakes past the due time.
    public func wake() {
        guard let nextDue, now() >= nextDue else { return }
        start(after: .zero)
    }
}
