import Foundation
import Observation
import UserNotifications
import os

@MainActor @Observable
public final class AlertScheduler {
    static let lateTolerance: TimeInterval = 5
    static let testBannerID = "meqat.test-banner"

    public private(set) var notificationsAuthorized = false
    @ObservationIgnored public var onFullScreen: ((PlannedAlert) -> Void)?
    @ObservationIgnored public var onBannerFired: ((PlannedAlert) -> Void)?

    @ObservationIgnored private let center: NotificationCentering
    @ObservationIgnored private let timer: AlertTimer
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let timeZone: @Sendable () -> TimeZone
    @ObservationIgnored private let plan: @MainActor () -> [PlannedAlert]
    @ObservationIgnored private let logger = Logger(subsystem: MeqatCore.bundleIdentifier, category: "alerts")

    @ObservationIgnored private var current: [PlannedAlert] = []
    @ObservationIgnored private var rebuilding = false
    @ObservationIgnored private var rebuildPending = false
    @ObservationIgnored private var suspended = false

    public init(
        center: NotificationCentering,
        timer: AlertTimer,
        now: @escaping @Sendable () -> Date = { Date() },
        timeZone: @escaping @Sendable () -> TimeZone = { .current },
        plan: @escaping @MainActor () -> [PlannedAlert]
    ) {
        self.center = center
        self.timer = timer
        self.now = now
        self.timeZone = timeZone
        self.plan = plan
    }

    public func requestRebuild() {
        suspended = false
        rebuildPending = true
        guard !rebuilding else { return }
        rebuilding = true
        Task {
            while rebuildPending {
                rebuildPending = false
                await rebuild()
            }
            rebuilding = false
        }
    }

    public func suspend() {
        suspended = true
        rebuildPending = false
        current = []
        center.removeAllPendingNotificationRequests()
        timer.cancel()
    }

    private func rebuild() async {
        current = plan()
        center.removeAllPendingNotificationRequests()
        for alert in current where alert.style == .banner {
            guard !suspended else { break }
            do { try await center.add(request(for: alert)) } catch {
                logger.error("Adding a banner request failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if suspended {
            center.removeAllPendingNotificationRequests()
        } else {
            arm(after: now())
        }
        await refreshAuthorization()
    }

    /// Re-reads notification permission without rebuilding the schedule.
    public func refreshAuthorization() async {
        notificationsAuthorized = await center.isAuthorized()
    }

    /// Delivers a banner at once so the user can check notifications work. Leaves the plan and timer alone.
    public func sendTestBanner() async {
        let content = UNMutableNotificationContent()
        content.title = "Meqat test alert"
        content.sound = .default
        let request = UNNotificationRequest(identifier: Self.testBannerID, content: content, trigger: nil)
        do { try await center.add(request) } catch {
            logger.error("Adding the test banner failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func request(for alert: PlannedAlert) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = ""
        content.sound = .default
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone()
        let parts = calendar.dateComponents(in: timeZone(), from: alert.fireDate)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(
                timeZone: parts.timeZone, year: parts.year, month: parts.month, day: parts.day,
                hour: parts.hour, minute: parts.minute, second: parts.second),
            repeats: false)
        return UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger)
    }

    /// Arms the timer for the earliest alert after `instant`, of either style.
    private func arm(after instant: Date) {
        guard let next = current.map(\.fireDate).filter({ $0 > instant }).min() else {
            timer.cancel()
            return
        }
        timer.arm(at: next) { [weak self] in self?.fire(at: next) }
    }

    private func fire(at instant: Date) {
        if now().timeIntervalSince(instant) <= Self.lateTolerance {
            for alert in current where alert.fireDate == instant {
                if alert.style == .fullScreen { onFullScreen?(alert) } else { onBannerFired?(alert) }
            }
        }
        arm(after: instant)
    }
}
