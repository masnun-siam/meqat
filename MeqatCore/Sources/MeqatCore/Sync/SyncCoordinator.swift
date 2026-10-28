import Foundation
import Observation
import os

public enum SyncTrigger: Sendable {
    case periodic, wake, settingsChanged, locationChanged, timeZoneChanged, refreshNow
}

@MainActor @Observable
public final class SyncCoordinator {
    static let backoff: [Duration] = [.seconds(15), .seconds(30), .seconds(60), .seconds(300)]
    static let debounce: Duration = .seconds(1)

    public private(set) var status = SyncStatus()
    public private(set) var cache: TimingsCache?
    @ObservationIgnored public var onCacheReplaced: ((TimingsCache) -> Void)?

    @ObservationIgnored private let client: AladhanFetching
    @ObservationIgnored private let store: CacheStore
    @ObservationIgnored private let parameters: @MainActor () -> FetchParameters?
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let timeZone: @Sendable () -> TimeZone
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let logger = Logger(subsystem: MeqatCore.bundleIdentifier, category: "sync")

    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var runningParameters: FetchParameters?
    @ObservationIgnored private var followUpPending = false
    @ObservationIgnored private var waitTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var retryIndex = 0

    public init(
        client: AladhanFetching,
        store: CacheStore,
        parameters: @escaping @MainActor () -> FetchParameters?,
        now: @escaping @Sendable () -> Date = { Date() },
        timeZone: @escaping @Sendable () -> TimeZone = { .current },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.client = client
        self.store = store
        self.parameters = parameters
        self.now = now
        self.timeZone = timeZone
        self.sleep = sleep
        cache = store.load()
    }

    public func trigger(_ trigger: SyncTrigger) {
        if trigger == .settingsChanged {
            debounceTask?.cancel()
            debounceTask = Task { [sleep] in
                try? await sleep(Self.debounce)
                guard !Task.isCancelled else { return }
                debounceTask = nil
                handle(.locationChanged)
            }
        } else {
            handle(trigger)
        }
    }

    public func clearCachedLocation() {
        guard let cache else { return }
        let stripped = cache.strippingLocation()
        do { try store.save(stripped) } catch { logger.warning("cache save failed: \(Self.kind(of: error), privacy: .public)") }
        self.cache = stripped
        onCacheReplaced?(stripped)
    }

    // MARK: Trigger handling

    private func handle(_ trigger: SyncTrigger) {
        guard let current = parameters() else { return }
        if syncTask != nil {
            if current != runningParameters { followUpPending = true }
            return
        }
        if status.isWaitingToRetry && trigger == .periodic { return }
        if trigger != .refreshNow {
            let today = LocalDate(now(), timeZone: timeZone())
            guard SyncPolicy.needsFetch(cache: cache, current: current, today: today) else { return }
        }
        cancelWait()
        retryIndex = 0
        startSync(current)
    }

    private func cancelWait() {
        waitTask?.cancel()
        waitTask = nil
        status.isWaitingToRetry = false
    }

    // MARK: One sync

    private func startSync(_ params: FetchParameters) {
        runningParameters = params
        status.isFetching = true
        syncTask = Task { await runSync(params) }
    }

    private func runSync(_ params: FetchParameters) async {
        var failure: Error?
        do {
            let today = LocalDate(now(), timeZone: timeZone())
            var days: [LocalDate: DayTimings] = [:]
            for month in SyncPolicy.months(today: today) {
                for day in try await client.fetchMonth(month, parameters: params) { days[day.date] = day }
            }
            let fetchedAt = now()
            let fresh = TimingsCache(parameters: params, fetchedAt: fetchedAt, days: days)
            try store.save(fresh)
            cache = fresh
            onCacheReplaced?(fresh)
            status.lastSuccess = fetchedAt
            status.offlineSince = nil
            status.lastFailure = nil
        } catch {
            failure = error
        }
        syncTask = nil
        runningParameters = nil
        status.isFetching = false

        if let failure { recordFailure(failure) }
        if followUpPending {
            followUpPending = false
            if let next = parameters(), next != params {
                cancelWait()
                retryIndex = 0
                startSync(next)
                return
            }
        }
        if let failure, Self.isRetryable(failure) { scheduleRetry(after: failure) }
    }

    private func recordFailure(_ error: Error) {
        if error as? AladhanError == .cityNotFound {
            status.lastFailure = .cityNotFound
            logger.warning("sync failed: city not found")
        } else {
            status.lastFailure = .network
            status.offlineSince = status.offlineSince ?? now()
        }
    }

    private static func isRetryable(_ error: Error) -> Bool {
        error as? AladhanError != .cityNotFound
    }

    private func scheduleRetry(after error: Error) {
        guard retryIndex < Self.backoff.count else {
            logger.warning("sync failed: \(Self.kind(of: error), privacy: .public), giving up until next periodic")
            return
        }
        let delay = Self.backoff[retryIndex]
        retryIndex += 1
        logger.warning("sync failed: \(Self.kind(of: error), privacy: .public), retry in \(delay.components.seconds)s")
        status.isWaitingToRetry = true
        waitTask = Task { [sleep] in
            try? await sleep(delay)
            guard !Task.isCancelled else { return }
            waitTask = nil
            status.isWaitingToRetry = false
            if let params = parameters() { startSync(params) }
        }
    }

    /// Error kind only, never a URL, coordinates or place name.
    private static func kind(of error: Error) -> String {
        switch error as? AladhanError {
        case .http(let code)?: return "http \(code)"
        case .apiCode(let code)?: return "api code \(code)"
        case .bodyTooLarge?: return "body too large"
        case .invalidResponse?: return "invalid response"
        case .noLocation?: return "no location"
        case .cityNotFound?: return "city not found"
        case nil: return error is URLError ? "connection error" : "save or other error"
        }
    }
}
