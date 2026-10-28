import AppKit
import MeqatCore
import Observation
import UserNotifications
import os

/// The composition root: owns every component and wires them together.
@MainActor
final class AppEnvironment {
    private static let bannerNowDuration: Duration = .seconds(5 * 60)
    private static let couldntRefreshDuration: Duration = .seconds(5)

    private let store = SettingsStore()
    private let provider = LocationProvider()
    private let coordinator: SyncCoordinator
    private let scheduler: AlertScheduler
    private let overlay = OverlayController()
    private let loginItem = MainAppLoginItem()
    private let context = SettingsContext()
    private let activity = NSBackgroundActivityScheduler(identifier: "com.masnunsiam.Meqat.periodic")
    private var statusItem: StatusItemController!
    private var systemEvents: SystemEvents?

    private var bannerNow: EventID?
    private var bannerNowTask: Task<Void, Never>?
    private var showsCouldntRefresh = false
    private var couldntRefreshTask: Task<Void, Never>?
    private var refreshPending = false
    private var lookupPending = false
    private var lookupSawFetch = false

    init() {
        let store = store
        let provider = provider
        let directory = (try? CacheStore.defaultDirectory()) ?? FileManager.default.temporaryDirectory
        let coordinator = SyncCoordinator(client: AladhanClient(), store: CacheStore(directory: directory)) {
            Composition.fetchParameters(location: provider.state, settings: store.settings, timeZone: .current)
        }
        self.coordinator = coordinator
        scheduler = AlertScheduler(center: UNUserNotificationCenter.current(), timer: DispatchAlertTimer()) {
            let plan = Composition.plan(cache: coordinator.cache, settings: store.settings, now: Date(), timeZone: .current)
            #if DEBUG
                Self.logPlan(plan)
            #endif
            return plan
        }
    }

    func start() {
        SettingsWindowController.shared.store = store
        SettingsWindowController.shared.context = context
        statusItem = StatusItemController(state: { [unowned self] in menuState() }, actions: menuActions())
        wire()

        provider.apply(store.settings.location)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        LoginItemSync.apply(store.settings.general.launchAtLogin, to: loginItem)
        syncAndRebuild(.periodic)
        activity.interval = 2 * 3600
        activity.tolerance = 10 * 60
        activity.repeats = true
        activity.schedule { [weak self] completion in
            Task { @MainActor in self?.syncAndRebuild(.periodic) }
            completion(.finished)
        }
        track()
        refreshAll()
    }

    // MARK: Wiring

    private func wire() {
        store.onChange = { [unowned self] old, new in settingsChanged(old, new) }
        provider.onChange = { [unowned self] in
            coordinator.trigger(.locationChanged)
            refreshAll()
        }
        coordinator.onCacheReplaced = { [unowned self] cache in
            if Composition.isStale(cache, mode: store.settings.location.mode) { coordinator.clearCachedLocation() }
            scheduler.requestRebuild()
            refreshAll()
        }
        scheduler.onFullScreen = { [unowned self] alert in
            overlay.show(
                OverlayContent(
                    eventName: alert.eventID.displayName, start: alert.eventInterval.start,
                    end: alert.eventInterval.end, holdSeconds: store.settings[event: alert.eventID].overlayHoldSeconds))
        }
        scheduler.onBannerFired = { [unowned self] alert in
            if !scheduler.notificationsAuthorized { showBannerNow(alert.eventID) }
        }
        systemEvents = SystemEvents(
            .init(
                willSleep: { [unowned self] in scheduler.suspend() },
                didWake: { [unowned self] in
                    syncAndRebuild(.wake)
                    statusItem.refresh()
                    statusItem.rearmTicker()
                },
                timeZoneChanged: { [unowned self] in
                    syncAndRebuild(.timeZoneChanged)
                    refreshAll()
                    statusItem.rearmTicker()
                },
                clockChanged: { [unowned self] in
                    scheduler.requestRebuild()
                    refreshAll()
                    statusItem.rearmTicker()
                },
                willTerminate: { [unowned self] in scheduler.suspend() }))
    }

    private func settingsChanged(_ old: AppSettings, _ new: AppSettings) {
        if old.location.mode != new.location.mode { coordinator.clearCachedLocation() }
        if old.location != new.location {
            provider.apply(new.location)
            if new.location.mode == .manual { startLookup() }
        }
        if old.general.launchAtLogin != new.general.launchAtLogin {
            LoginItemSync.apply(new.general.launchAtLogin, to: loginItem)
        }
        if old.location != new.location || old.general.method != new.general.method || old.general.school != new.general.school {
            coordinator.trigger(.settingsChanged)
        }
        scheduler.requestRebuild()
        refreshAll()
    }

    private func syncAndRebuild(_ trigger: SyncTrigger) {
        coordinator.trigger(trigger)
        scheduler.requestRebuild()
    }

    /// Re-registers itself, since `withObservationTracking` fires once.
    private func track() {
        withObservationTracking {
            _ = coordinator.status
            _ = provider.state
            _ = scheduler.notificationsAuthorized
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observedStateChanged()
                self?.track()
            }
        }
    }

    private func observedStateChanged() {
        let status = coordinator.status
        if refreshPending, !status.isFetching {
            refreshPending = false
            if status.lastFailure != nil { showCouldntRefresh() }
        }
        updateLookup(status)
        refreshAll()
    }

    // MARK: Transient state

    private func showBannerNow(_ id: EventID) {
        bannerNow = id
        bannerNowTask?.cancel()
        bannerNowTask = Task { [weak self] in
            try? await Task.sleep(for: Self.bannerNowDuration)
            guard !Task.isCancelled else { return }
            self?.clearBannerNow()
        }
        statusItem.refresh()
    }

    private func clearBannerNow() {
        bannerNowTask?.cancel()
        guard bannerNow != nil else { return }
        bannerNow = nil
        statusItem.refresh()
    }

    private func showCouldntRefresh() {
        showsCouldntRefresh = true
        couldntRefreshTask?.cancel()
        couldntRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: Self.couldntRefreshDuration)
            guard !Task.isCancelled else { return }
            self?.showsCouldntRefresh = false
            self?.refreshAll()
        }
    }

    private func startLookup() {
        lookupPending = true
        lookupSawFetch = false
        context.lookupStatus = .idle
    }

    /// Settles the Location pane's lookup line after the first sync a manual city triggers.
    private func updateLookup(_ status: SyncStatus) {
        guard lookupPending else { return }
        if status.isFetching {
            lookupSawFetch = true
            context.lookupStatus = .lookingUp
        } else if lookupSawFetch {
            lookupPending = false
            switch status.lastFailure {
            case nil: context.lookupStatus = .found
            case .cityNotFound?: context.lookupStatus = .cityNotFound
            case .network?: context.lookupStatus = .unreachable
            }
        }
    }

    // MARK: Menu and settings state

    private func menuActions() -> MenuActions {
        var actions = MenuActions()
        actions.refreshNow = { [unowned self] in refreshNow() }
        actions.tryAgain = { [unowned self] in refreshNow() }
        actions.openSettings = { [unowned self] in openSettings(.general) }
        actions.openLocationPane = { [unowned self] in openSettings(.location) }
        actions.dropdownOpened = { [unowned self] in clearBannerNow() }
        return actions
    }

    private func refreshNow() {
        coordinator.trigger(.refreshNow)
        refreshPending = coordinator.status.isFetching
    }

    private func openSettings(_ pane: SettingsPane) {
        refreshContext()
        SettingsWindowController.shared.show(pane: pane)
    }

    private func menuState() -> MenuState {
        let now = Date()
        let timeZone = TimeZone.current
        let settings = store.settings
        let cache = coordinator.cache
        return MenuPresenter.present(
            MenuInput(
                now: now, timeZone: timeZone,
                events: Composition.events(cache: cache, settings: settings, now: now, timeZone: timeZone),
                styles: settings.events.mapValues(\.style),
                place: settings.location.placeName(timeZone: timeZone),
                hasScheduleForToday: cache?.day(LocalDate(now, timeZone: timeZone)) != nil,
                sync: MenuSyncInfo(coordinator.status),
                location: MenuLocationInfo(provider.state),
                notificationsAuthorized: scheduler.notificationsAuthorized,
                bannerNow: bannerNow,
                showsCouldntRefresh: showsCouldntRefresh))
    }

    private func refreshAll() {
        statusItem?.refresh()
        refreshContext()
    }

    private func refreshContext() {
        let now = Date()
        let timeZone = TimeZone.current
        let today = LocalDate(now, timeZone: timeZone)
        let todays = Composition.events(cache: coordinator.cache, settings: store.settings, now: now, timeZone: timeZone).filter {
            $0.date == today
        }
        context.calculatedWindows = Dictionary(
            todays.compactMap { e in e.calculatedInterval.map { (e.id, $0) } }, uniquingKeysWith: { first, _ in first })
        context.place = store.settings.location.placeName(timeZone: timeZone)
        context.coordinatesText = provider.coordinates.map { String(format: "%.2f, %.2f", $0.latitude, $0.longitude) }
        context.lastSyncText = coordinator.status.lastSuccess.map { Self.lastSyncFormat(timeZone).string(from: $0) }
    }

    private static func lastSyncFormat(_ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "d MMM HH:mm"
        return f
    }

    #if DEBUG
        /// Ids and fire times only: titles and places stay out of the log.
        private static func logPlan(_ plan: [PlannedAlert]) {
            let logger = Logger(subsystem: MeqatCore.bundleIdentifier, category: "app")
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            for alert in plan where alert.style == .banner {
                logger.debug("pending: \(alert.id, privacy: .public)@\(f.string(from: alert.fireDate), privacy: .public)")
            }
        }
    #endif
}
