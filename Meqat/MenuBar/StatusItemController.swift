import AppKit
import MeqatCore
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let state: @MainActor () -> MenuState
    private let actions: MenuActions
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let host = NSHostingController(rootView: AnyView(EmptyView()))
    private var ticker: MinuteTicker!

    init(state: @escaping @MainActor () -> MenuState, actions: MenuActions) {
        self.state = state
        self.actions = actions
        super.init()
        popover.behavior = .transient
        popover.contentViewController = host
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        ticker = MinuteTicker { [weak self] in self?.refresh() }
        refresh()
    }

    func rearmTicker() { ticker.rearm() }

    /// Re-reads the state and updates the title and, while open, the dropdown.
    func refresh() {
        let current = state()
        statusItem.button?.title = current.statusTitle
        statusItem.button?.setAccessibilityLabel(current.statusAccessibilityLabel)
        host.rootView = AnyView(MenuDropdownView(state: current, actions: actions))
        if popover.isShown { popover.contentSize = host.view.fittingSize }
    }

    @objc private func toggle() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        actions.dropdownOpened()
        refresh()
        popover.contentSize = host.view.fittingSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}
