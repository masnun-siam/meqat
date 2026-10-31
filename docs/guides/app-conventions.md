# App target conventions

Read before changing `Meqat/` (AppKit + SwiftUI, macOS 14+). The app target wires and renders `MeqatCore`; it holds no logic. Every rule names the file that sets it.

## Layout

| Folder | Holds | Anchor file |
|---|---|---|
| `Meqat/main.swift` | Entry point | itself |
| `Meqat/App` | Lifecycle, composition root, system notifications | `AppEnvironment.swift` |
| `Meqat/MenuBar` | `NSStatusItem`, popover, minute ticker | `StatusItemController.swift` |
| `Meqat/Overlay` | Full-screen alert panels | `OverlayController.swift` |
| `Meqat/Settings` | Settings window and panes | `SettingsWindowController.swift` |
| `Meqat/Debug` | DEBUG-only harnesses | `DebugHarness.swift` |
| `Config/` | `Meqat.entitlements` | `Meqat.entitlements` |

## Lifecycle and entry point

- No `@main`, no SwiftUI `App`. `main.swift` creates `AppDelegate` and calls `NSApplication.shared.run()`.
- `AppDelegate.applicationDidFinishLaunching` sets `.accessory` policy, creates one `AppEnvironment`, calls `start()`, and keeps it in a property.
- No Dock icon and no main menu: `INFOPLIST_KEY_LSUIElement = YES` in `Meqat.xcodeproj/project.pbxproj` (both configs). Info.plist is generated (`GENERATE_INFOPLIST_FILE = YES`); add keys as `INFOPLIST_KEY_*` build settings, not a plist file.
- App icon: `Meqat/Assets.xcassets/AppIcon.appiconset`, wired by `ASSETCATALOG_COMPILER_APPICON_NAME` (both configs).
- There is no Dock or main-menu way to open Settings. The status item popover is the only entry (`MenuActions.openSettings`).

## Composition: `AppEnvironment`

`Meqat/App/AppEnvironment.swift` is the only place that constructs and connects `MeqatCore` objects (`SettingsStore`, `LocationProvider`, `SyncCoordinator`, `AlertScheduler`, `MainAppLoginItem`, `Composition`, `MenuPresenter`).

- Wiring is closures. Core types expose `onChange`, `onCacheReplaced`, `onFullScreen`, `onBannerFired`; `wire()` assigns them, always with `[unowned self]`. Follow this for new callbacks.
- UI components receive closures, not the environment. `StatusItemController(state:actions:)` takes a state closure and a `MenuActions` struct (`MenuActions.swift`); see `menuActions()`.
- Core presents, the app renders. The app builds a `MenuInput`, calls `MenuPresenter.present`, and renders the returned `MenuState`. Do the same for new UI: add the presenter or state to `MeqatCore`, render it here.
- After any state change, call `refreshAll()` (menu plus `SettingsContext`). Transient UI state (`bannerNow`, `showsCouldntRefresh`) is a field plus a cancellable `Task` with a `Self.*Duration` constant.
- Exception: `SettingsWindowController.shared` is a singleton set up by `start()` (`store`, `context`), not injected.

## AppKit vs SwiftUI split

| Surface | AppKit owns | SwiftUI owns | File |
|---|---|---|---|
| Menu bar | `NSStatusItem` button title, `NSPopover` (`.transient`) | Dropdown body | `StatusItemController.swift`, `MenuDropdownView.swift` |
| Overlay | `OverlayPanel` (`NSPanel`), one per `NSScreen`, lock/sleep/screen-change handling | `OverlayView` in an `NSHostingView` | `OverlayController.swift`, `OverlayPanel.swift`, `OverlayView.swift` |
| Settings | `NSWindow` created lazily and reused | `NavigationSplitView` and panes in an `NSHostingController` | `SettingsWindowController.swift`, `SettingsView.swift` |

- AppKit shells hold state and lifecycle; SwiftUI views are passed state and closures. Views never reach for `AppEnvironment`.
- Menu bar refresh replaces `host.rootView` with a fresh `MenuDropdownView` on each `refresh()` (`StatusItemController`); it does not mutate shared view state.
- The overlay panel is `.borderless, .nonactivatingPanel` at `CGShieldingWindowLevel`, `.canJoinAllSpaces`, `canBecomeKey = true`. Keep these; see `OverlayPanel.swift`.
- `OverlayController` hides panels while the screen is locked or the screensaver runs, pauses the hold during sleep, and rebuilds panels on screen-parameter changes. Add new hide conditions through its `observe(...)` helper.

## Main actor and threading

- UI types are `@MainActor`: `AppEnvironment`, `SystemEvents`, `StatusItemController`, `MinuteTicker`, `OverlayController`, `SettingsWindowController`, `SettingsContext`, `SettingsNavigation`.
- Notification and `Timer` callbacks use `queue: .main` / main run loop, then `MainActor.assumeIsolated { ... }`. Pattern: `SystemEvents.add`, `MinuteTicker.rearm`, `OverlayController.observe`/`startTimer`. Do not use `DispatchQueue.global` or detached tasks in the app target.
- Async work from callbacks: `Task { @MainActor in ... }` (`AppEnvironment.start`, `track`) or `Task { [weak self] in ... }` inside a `@MainActor` type.
- Exceptions (not `@MainActor`): `AppDelegate`, `OverlayPanel`, `MenuActions` (its closures are `@MainActor`), `OverlayModel`, and the debug harnesses, which use `MainActor.assumeIsolated` internally.
- Build uses `SWIFT_VERSION = 5.0` with no strict-concurrency setting, so isolation is by convention; keep it explicit.

## Observation

- Observable state uses the Observation framework: `@MainActor @Observable` (`SettingsContext`, `SettingsNavigation`; core's `SettingsStore`, `LocationProvider`, `AlertScheduler`).
- Panes take `@Bindable var store: SettingsStore` and bind directly (`$store.settings.general...`).
- AppKit code observes core state with `withObservationTracking` in `AppEnvironment.track()`, which re-registers itself in `onChange` because tracking fires once. List every observed property inside the `withObservationTracking` closure.
- Non-observable callbacks use `onChange` closures (`SettingsStore.onChange` marked `@ObservationIgnored` in core); handle them in `AppEnvironment.settingsChanged`.
- Exception: `OverlayModel` in `OverlayView.swift` is `ObservableObject` with `@Published`, not `@Observable`. New code should use `@Observable`.

## Settings panes

Files in `Meqat/Settings/`; one `SettingsPane` enum case per sidebar entry.

- `SettingsPane.swift` enum (`general`, `location`, `event(EventID)`) drives `SettingsView.swift`'s sidebar and its `switch`. New pane: add a case, a sidebar row, and a `switch` branch.
- Each pane is a `struct XPane: View` with `Form { ... }.formStyle(.grouped)` (`GeneralPane`, `LocationPane`, `EventPane`).
- Settings data: `let/@Bindable store: SettingsStore`, edited in place. Runtime read-only data (calculated windows, place, lookup status, last sync) comes from `let context: SettingsContext`. `AppEnvironment.refreshContext()` fills it; panes never compute it.
- Numeric inputs clamp with `Bounds.clamped(_, to: Bounds.*)` from core (`DurationRow` in `GeneralPane`, `NumberRow` in `EventPane`). Private row helpers live at the bottom of the pane file.
- Every setting carries a help line: a second `Text` in the control's label (`label:` closure), or a `Section` footer. `DurationRow` and `NumberRow` take a `help` string; keep the inner `TextField`/`Stepper` titled with `.labelsHidden()`.
- Pane-local `@State` is for uncommitted input only (`LocationPane` city/country fields); commit through the store.
- Destructive actions use `confirmationDialog` (`GeneralPane` reset).
- `SettingsDebugHarness` has `pane(_:)` mapping names to `SettingsPane`; update it when adding a pane that needs a name.

## Accessibility and Reduce Motion

- Status item: `setAccessibilityLabel(current.statusAccessibilityLabel)` on every `refresh()` (`StatusItemController`). Label text comes from core's `MenuState`.
- Menu rows: `.accessibilityElement(children: .ignore)` plus `.accessibilityLabel(row.accessibilityLabel)` (`MenuRowView` in `MenuDropdownView.swift`). Do not rely on the marker glyphs.
- Overlay: heading trait on the event name; VoiceOver announcements via `NSAccessibility.post(.announcementRequested, priority: .high)` in `OverlayController.post`, on show, every 10 s of countdown and when Dismiss becomes available.
- Reduce Motion: only `OverlayView` reads `@Environment(\.accessibilityReduceMotion)` and turns off `.contentTransition(.numericText())`. Its `.animation(nil, ...)` disables other animation. New animation must honor it the same way.
- Overlay text is white on a fixed gradient with contrast documented inline (`OverlayView.gradient`); re-check contrast if colors change.
- Other settings and menu views have no custom accessibility code; they rely on standard controls. Pass a title to `TextField`/`Stepper` and hide it with `.labelsHidden()` (`DurationRow`) so VoiceOver still has a label.

## Debug harnesses

Launch: `--args -MeqatDebugHarness <Name>` (Xcode scheme args or the binary). DEBUG only.

- `AppDelegate` calls `DebugHarnessLauncher.runIfRequested()` first and returns early, so **no** `AppEnvironment`, status item or network runs in harness mode.
- `DebugHarnessLauncher` (`DebugHarness.swift`) resolves `NSClassFromString("MeqatDebug<Name>Harness")`; the class must conform to `@objc protocol DebugHarness` (`static func run()`).
- Existing: `Overlay`, `Menu`, `Settings`, `LoginItem`. Extra args are read from `UserDefaults` (`-MeqatDebugPane`, `-MeqatDebugHold`, `-MeqatDebugLookup`, `-MeqatDebugEmpty`, `-MeqatDebugUpdate`, `-MeqatDebugNow`, `-MeqatDebugTimeFormat`, `-MeqatDebugWindows`).

Add one:

1. Create `Meqat/Debug/<Name>DebugHarness.swift`, wrapped entirely in `#if DEBUG ... #endif`.
2. Declare `@objc(MeqatDebug<Name>Harness) final class <Name>DebugHarness: NSObject, DebugHarness` with `static func run()`. The explicit `@objc(...)` name is required for the lookup to work.
3. Do UI work inside `MainActor.assumeIsolated { }`. Keep strong references in a static (`MenuDebugHarness.controller`).
4. Feed it mock data; do not call the network. Document the launch args in the doc comment (see `SettingsDebugHarness`).
5. Nothing may reference harness code from non-DEBUG code except the `#if DEBUG` call in `AppDelegate`.

## Adding a Swift file

- `project.pbxproj` is **not** edited per file. `Meqat/` is a `PBXFileSystemSynchronizedRootGroup` (`objectVersion = 77`): any file under `Meqat/` joins the `Meqat` target on build. Create the file; do not touch the pbxproj.
- Exceptions: files outside `Meqat/` (such as `Config/Meqat.entitlements`) are plain file references, and `MeqatCore` is a local package reference. Changing either needs a pbxproj edit.
- Build: `xcodebuild -project Meqat.xcodeproj -scheme Meqat -configuration Debug -destination 'platform=macOS' CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGN_ENTITLEMENTS= DEVELOPMENT_TEAM= build`.
- Deployment target is 14.0 in both configs; do not use newer APIs without availability checks.

## Entitlements and permissions

`Config/Meqat.entitlements`: App Sandbox, `network.client`, `personal-information.location`. Hardened runtime is on. Do not add entitlements (file access, other network roles) without a human decision. Location usage strings are `INFOPLIST_KEY_NS*` build settings in the pbxproj. No third-party packages (`CLAUDE.md`).

## What must not go in the app target

| Do not | Instead | Example of the correct split |
|---|---|---|
| Compute times, windows, plans, formatting of menu text | `MeqatCore` (`Composition`, `MenuPresenter`, `AlertScheduler`) with XCTest | `AppEnvironment.menuState()` only builds inputs |
| Call Aladhan, read or write the cache, parse settings | `MeqatCore` (`SyncCoordinator`, `CacheStore`, `SettingsStore`) | `AppEnvironment.init` only constructs them |
| Validate or clamp settings values by ad-hoc rules | `Bounds`, `ManualCityInput`, `StaticTimeHint` in core | `GeneralPane`, `EventPane`, `LocationPane` |
| Hold overlay hold-time math | `OverlayHold` in core | `OverlayController` only calls it |
| Log titles, places or coordinates | Ids and times only, DEBUG-gated (`AppEnvironment.logPlan`) | |

Tolerated app-side logic is limited to presentation: `DateFormatter` for display, symbol mapping (`MenuRowView.symbol`), `Binding` adapters, and minute-boundary timing (`MinuteTicker`).
