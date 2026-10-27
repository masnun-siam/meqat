import AppKit

struct MenuActions {
    var refreshNow: @MainActor () -> Void = {}
    var openSettings: @MainActor () -> Void = {}
    var openLocationPane: @MainActor () -> Void = {}
    var tryAgain: @MainActor () -> Void = {}
    var dropdownOpened: @MainActor () -> Void = {}
    var quit: @MainActor () -> Void = { NSApp.terminate(nil) }
}
