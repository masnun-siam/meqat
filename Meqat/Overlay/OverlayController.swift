import AppKit
import SwiftUI
import MeqatCore

@MainActor
final class OverlayController {
    private var content: OverlayContent?
    private var model: OverlayModel?
    private var hold = OverlayHold(seconds: 0)
    private var panels: [OverlayPanel] = []
    private var timer: Timer?
    private var locked = false
    private var screensaver = false
    private var asleep = false
    private var wasSatisfied = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        observe(distributed, "com.apple.screenIsLocked") { $0.locked = true }
        observe(distributed, "com.apple.screenIsUnlocked") { $0.locked = false }
        observe(distributed, "com.apple.screensaver.didstart") { $0.screensaver = true }
        observe(distributed, "com.apple.screensaver.didstop") { $0.screensaver = false }
        observe(workspace, NSWorkspace.willSleepNotification.rawValue) { $0.asleep = true }
        observe(workspace, NSWorkspace.didWakeNotification.rawValue) { $0.asleep = false }
        observe(.default, NSApplication.didChangeScreenParametersNotification.rawValue, rebuild: true) { _ in }
    }

    deinit {
        for (center, token) in observers { center.removeObserver(token) }
    }

    private var isHidden: Bool { locked || screensaver }

    func show(_ content: OverlayContent) {
        self.content = content
        hold = OverlayHold(seconds: content.holdSeconds)
        wasSatisfied = false
        if let model {
            model.content = content
        } else {
            model = OverlayModel(content: content)
        }
        model?.remaining = content.holdSeconds
        startTimer()
        apply()
    }

    func dismiss() {
        timer?.invalidate()
        timer = nil
        closePanels()
        content = nil
        model = nil
    }

    // MARK: State

    /// Sets a lock/sleep flag, then reconciles panels and the hold with the new state.
    private func observe(
        _ center: NotificationCenter, _ name: String, rebuild: Bool = false,
        change: @escaping @MainActor (OverlayController) -> Void
    ) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let wasHidden = self.isHidden
                change(self)
                if rebuild { self.closePanels() }
                // Unlock after the event ended: the overlay is dropped, never shown.
                if wasHidden, !self.isHidden, let end = self.content?.end, Date() >= end {
                    self.dismiss()
                    return
                }
                self.apply()
            }
        }
        observers.append((center, token))
    }

    /// Panels visible and hold running only when not locked; hold also stops while asleep.
    private func apply() {
        guard content != nil else { return }
        let now = Date()
        if isHidden {
            closePanels()
            hold.pause(at: now)
            return
        }
        if panels.isEmpty { buildPanels() }
        if asleep { hold.pause(at: now) } else { hold.resume(at: now) }
        tick()
    }

    // MARK: Panels

    private func buildPanels() {
        guard let model else { return }
        panels = NSScreen.screens.map { screen in
            let panel = OverlayPanel(screen: screen)
            panel.contentView = NSHostingView(rootView: OverlayView(model: model) { [weak self] in self?.dismissIfSatisfied() })
            panel.onCancel = { [weak self] in self?.dismissIfSatisfied() }
            return panel
        }
        NSApp.activate()
        panels.forEach { $0.orderFrontRegardless() }
        panels.first?.makeKeyAndOrderFront(nil)
        announce()
    }

    private func closePanels() {
        panels.forEach { $0.orderOut(nil); $0.contentView = nil }
        panels = []
    }

    private func dismissIfSatisfied() {
        if hold.isSatisfied(at: Date()) { dismiss() }
    }

    // MARK: Countdown

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let model, let content else { return }
        let remaining = Int(hold.remaining(at: Date()).rounded(.up))
        model.remaining = remaining
        guard !isHidden, !asleep else { return }
        if remaining == 0, !wasSatisfied {
            wasSatisfied = true
            post("\(content.eventName) alert. Dismiss is available")
        } else if remaining > 0, remaining % 10 == 0 {
            announce()
        }
    }

    private func announce() {
        guard let content, let model else { return }
        post("\(content.eventName) alert. Dismiss available in \(model.remaining) seconds")
    }

    private func post(_ text: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}
