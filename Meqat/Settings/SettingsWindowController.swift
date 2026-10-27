import AppKit
import MeqatCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    /// Set by the app wiring (or the debug harness) before the first `show`.
    var store: SettingsStore!
    var context = SettingsContext()

    private let navigation = SettingsNavigation()
    private var window: NSWindow?

    func show(pane: SettingsPane) {
        navigation.selection = pane
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Meqat Settings"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: SettingsView(navigation: navigation, store: store, context: context))
        window.center()
        return window
    }
}
