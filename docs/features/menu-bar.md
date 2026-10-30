# Menu bar

Covers: MeqatCore/Sources/MeqatCore/Menu/, Meqat/MenuBar/, Meqat/App/AppEnvironment.swift, Meqat/Debug/MenuDebugHarness.swift, MeqatCore/Tests/MeqatCoreTests/MenuPresenterTests.swift

The status item title and the dropdown popover. All text and state logic is pure in MeqatCore; the app only renders it. Conventions: [meqatcore-conventions](../guides/meqatcore-conventions.md), [app-conventions](../guides/app-conventions.md). Inputs come from [events.md](events.md), [prayer-times-sync.md](prayer-times-sync.md), [location.md](location.md).

```mermaid
flowchart LR
    AE[AppEnvironment.menuState] --> MI[MenuInput]
    MI --> MP[MenuPresenter.present]
    MP --> MS[MenuState]
    MS --> SI[StatusItemController.refresh]
    SI --> T[button title + accessibility label]
    SI --> D[MenuDropdownView in NSPopover]
    MT[MinuteTicker] --> SI
    D -->|MenuActions| AE
```

## MenuInput (no clock reads, no I/O)

`now`, `timeZone`, `events` (engine output for yesterday..day after tomorrow), `styles` (per-event `AlertStyle`), `place`, `hasScheduleForToday`, `sync: MenuSyncInfo`, `location: MenuLocationInfo`, `notificationsAuthorized`, `bannerNow`, `showsCouldntRefresh`, `updateNotice: UpdateNotice?` (version and release URL) and `checksForUpdates` (defaults `nil`, `true`). `AppEnvironment.menuState()` builds it; `MenuSyncInfo(SyncStatus)` and `MenuLocationInfo(LocationState)` map core state (in `App/Composition.swift`).

## Status title (first match wins)

| Condition | Title |
|---|---|
| inside a prohibited window (even if its alerts are disabled) | `⛔ Shuruq ends in 12m` |
| `bannerNow` set | `● Asr now` |
| a current non-disabled event exists | `☾ Dhuhr ends in 1h 11m` |
| a next non-disabled event exists | `☾ Asr in 1h 11m` |
| otherwise, or no schedule today | `☾` (label "Meqat") |

- Countdowns round down to whole minutes: `<1m`, `12m`, `1h 0m`. Spoken form goes to `statusAccessibilityLabel`.
- "Current" = valid event with `start <= now < end` whose style is not `.disabled`; if several overlap, the latest start wins. May be yesterday's Isha past midnight.
- "Next" = earliest valid event starting after `now` whose style is not `.disabled`; may be tomorrow's.
- `bannerNow` is set by `AppEnvironment.showBannerNow` when a banner fires but notifications are not authorized; it clears after 5 min (`bannerNowDuration`) or when the dropdown opens (`MenuActions.dropdownOpened`).

## Dropdown (`MenuDropdownView`, 280 pt wide)

- Header `Wed 28 Oct · Dhaka` (nil without today's schedule).
- Rows (`MenuRow`, one per event of today): marker `none/done/current/next/prohibited` -> symbol, `timeText` (`04:52`, `06:05–06:20` for prohibited and Duha, `—` when invalid, `(prev. night)` suffix), `detailText` (`ends in 1h 11m` or `1h 11m`), per-row VoiceOver label. Past prohibited rows are dimmed. A Tahajjud carried from last night replaces today's row from its start.
- Empty state replaces rows when `hasScheduleForToday` is false (`MenuEmptyState`):

| State | Message | Button |
|---|---|---|
| `awaitingPermission` | Waiting for location permission… | Open Location settings |
| `fetching` | Fetching times… | none |
| `setLocation` | Set your location | Open Location settings |
| `cityNotFound` | City not found — check Location settings | Open Location settings |
| `offline` | No schedule — connect to the internet | Try again |

  Precedence: awaiting permission, then fetching (syncing or awaiting fix), then missing location, then last failure; no failure means fetching.
- "Notifications are off — Open System Settings" row when `!notificationsAuthorized` (opens the Notifications settings pane URL).
- `MenuState.updateRow` (`MenuUpdateRow`: `Update available — <x.y.z>` and the release URL) is set only when `updateNotice` is present and `checksForUpdates` is on, with or without a schedule. `MenuDropdownView` renders it as a link row above the footer divider (below the notifications-off row); clicking opens the URL and closes the popover via `dismiss`. Harness: `-MeqatDebugUpdate 1.4.0`.
- Footer text (first match): `Couldn't refresh`, `Syncing…`, `Offline — using cache from d MMM`, `Synced HH:mm` (today) or `Synced d MMM HH:mm`, empty. Times follow `MenuInput.timeFormat` (`h:mm a` when 12-hour). Buttons: Refresh now (disabled while fetching), Settings…, Quit.

## "Couldn't refresh"

`refreshNow()` sets `refreshPending` if a fetch started. When the observed `SyncStatus` stops fetching with a `lastFailure`, `showCouldntRefresh()` sets `showsCouldntRefresh` for 5 s (`couldntRefreshDuration`), then clears it.

## Actions (`MenuActions`, wired in `AppEnvironment.menuActions()`)

| Action | Effect |
|---|---|
| `refreshNow`, `tryAgain` | `coordinator.trigger(.refreshNow)` |
| `openSettings` | Settings window, General pane |
| `openLocationPane` | Settings window, Location pane |
| `dropdownOpened` | clears `bannerNow` |
| `quit` | `NSApp.terminate` |

## Refresh and ticker

- `StatusItemController.refresh()` re-reads state, sets title and accessibility label, swaps the popover root view and resizes it if shown. It is called on every observed change (`track()` over `coordinator.status`, `provider.state`, `scheduler.notificationsAuthorized`), settings change, and popover open.
- `MinuteTicker` fires 0.05 s after each wall-clock minute (tolerance 0.2 s) to update countdowns. `rearmTicker()` is called after wake, time zone change and clock change.

## Tests

`MenuPresenterTests`: next/rows, disabled Duha, prohibited precedence, crescent, countdown rounding, tomorrow after Isha, banner now, VoiceOver labels, invalid row, prev-night carry-over, empty-state precedence, footer variants, notifications row and place. `CompositionTests` covers the `MenuSyncInfo`/`MenuLocationInfo` mapping. The controller and views are untested; use the harness.

## Debug harness

`-MeqatDebugHarness Menu`: status item with a fixed mock day, clock starting at 13:52 and running on, Duha disabled, notifications off; actions print `action: <name>`. Add `-MeqatDebugEmpty offline` for the offline empty state.
