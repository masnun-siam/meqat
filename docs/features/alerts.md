# Alerts

Covers: MeqatCore/Sources/MeqatCore/Alerts/, MeqatCore/Sources/MeqatCore/App/Composition.swift, Meqat/App/AppEnvironment.swift, MeqatCore/Tests/MeqatCoreTests/AlertPlannerTests.swift, AlertSchedulerTests.swift, CompositionTests.swift

Per-event alerts: a banner (system notification) or a full-screen overlay at a computed time. Conventions: [meqatcore-conventions](../guides/meqatcore-conventions.md), [app-conventions](../guides/app-conventions.md). Event times come from the engine ([events.md](events.md)) and the cache ([prayer-times-sync.md](prayer-times-sync.md)); the overlay itself is in [overlay.md](overlay.md).

## Settings (per event, `EventSettings` in `Settings/AppSettings.swift`)

| Field | Meaning | Default | Bound |
|---|---|---|---|
| `startAlert` | `style` (`AlertStyle`: `.fullScreen`, `.banner`, `.disabled` = Off), `offsetMinutes` from event start | Banner (Off for `duha`, `tahajjud`), 0 | `Bounds.offsetMinutes` -60...60 |
| `endAlert` | `style`, `leadMinutes` before event end | Off, 15 | `Bounds.leadMinutes` 1...120 |
| `preWarning` | `style`, `leadMinutes` before event start | Off, 20 | 1...120 |
| `style` (read-only) | derived: Start's style if not Off, else End's, else Pre-warning's, else `.disabled`; each alert's `enabled` is derived as style is not Off. Both are still written for older builds | n/a | n/a |
| `overlayHoldSeconds` | minimum overlay hold | 60 | `Bounds.overlayHoldSeconds` 0...300 |

Details in [settings.md](settings.md).

## AlertPlanner (pure)

`AlertPlanner.plan(events:settings:now:timeZone:)` returns `[PlannedAlert]`; `Composition.plan` feeds it `Composition.events` (yesterday through today + 2).

| Kind (`AlertKind`) | Fires at | Style | Title |
|---|---|---|---|
| `.start` | start + `offsetMinutes` | `startAlert.style` | `Asr · 15:04`; prohibited: `⛔ Ghurub · avoid praying until 17:27` |
| `.end` | end - `leadMinutes` | `endAlert.style` | `Asr ends in 15 min` |
| `.preWarning` | start - `leadMinutes` | `preWarning.style` | `Asr in 20 min` (`⛔ ` prefix if prohibited) |

- Id: `<yyyy-MM-dd list date>.<eventID>.<kind>`, e.g. `2026-10-28.asr.start`. It is also the notification request identifier.
- Skipped: alerts whose own style is `.disabled` (all three Off yields nothing), events with no `interval` (invalid time), fire dates not in `(now, now + AlertPlanner.horizon]` (48 h).
- Sorted by `(fireDate, id)`. Banners are capped at `AlertPlanner.maxBanners` (60, soonest kept); full-screen alerts are never capped.
- Times in titles are formatted with `settings.general.timeFormat` (`HH:mm` or `h:mm a`) in the given time zone.
- `language` (default `.english`) picks the title text: Bangla names, wording from `Resources/bn.lproj/Alerts.strings` (keys are the English format strings) and Bangla digits via `Language.locale`, e.g. `আসর শেষ হতে ১৫ মিনিট বাকি`. The 12-hour AM/PM marker stays as macOS gives it. Ids stay Latin. `AlertScheduler.sendTestBanner(language:)` does the same for the test banner.

## AlertScheduler (`@MainActor @Observable`)

```mermaid
flowchart TD
    A[settings / sync / wake / clock / tz change] --> R[requestRebuild]
    R -->|coalesced: rebuildPending| B[rebuild]
    B --> P[plan closure -> Composition.plan]
    P --> C[removeAllPendingNotificationRequests]
    C --> D[add UNCalendarNotificationTrigger per banner]
    D --> E[arm timer at earliest fireDate, any style]
    E --> F{timer fires}
    F -->|within lateTolerance 5s| G{style}
    G -->|fullScreen| H[onFullScreen -> OverlayController.show]
    G -->|banner| I[onBannerFired]
    F -->|later than 5s| J[dropped]
    G --> K[arm next]
    J --> K
    S[willSleep / willTerminate] --> U[suspend: clear requests + cancel timer]
```

- Rebuild is idempotent: every rebuild wipes all pending requests and re-adds the planned banners. Concurrent `requestRebuild` calls merge into one extra pass (`rebuilding`/`rebuildPending`). `requestRebuild` also clears `suspended`.
- Banners are scheduled with the OS (`UNCalendarNotificationTrigger`, non-repeating, title only, default sound), so they fire even if the app is not running. Full-screen alerts depend on the in-process timer: one `DispatchAlertTimer` (wall-clock `DispatchSourceTimer`, `.strict`) armed at the next alert of either style.
- Late tolerance: `AlertScheduler.lateTolerance` = 5 s. A timer that wakes later than that (e.g. after sleep) drops the alert instead of showing a stale one; the timer then moves on.
- Suspension: `suspend()` runs on `willSleep` and `willTerminate`; it clears pending requests and the timer. On wake, `AppEnvironment` runs `syncAndRebuild(.wake)`. A rebuild that finds `suspended` set mid-flight removes what it added.
- `notificationsAuthorized` is refreshed after each rebuild (`isAuthorized()`: authorized or provisional). When false, a fired banner calls `onBannerFired`, which `AppEnvironment` turns into the status-item "now" state for 5 min ([menu-bar.md](menu-bar.md)); the menu also shows a "Notifications are off" row.
- A failed `center.add` is logged and the remaining banners still go in.

## Wiring (`Meqat/App/AppEnvironment.swift`)

- `scheduler.onFullScreen` builds `OverlayContent(eventName, start, end, timeoutSeconds, timeFormat, kindLine)` from the alert (`kindLine` = `alert.overlayLine`) and the general overlay timeout, then `overlay.show(_:)`.
- Rebuild triggers: any settings change (`settingsChanged`), cache replaced (`onCacheReplaced`), wake, time zone change, clock change, launch (`syncAndRebuild(.periodic)`), and a 2 h `NSBackgroundActivityScheduler`.
- Notification permission is requested at launch (`.alert`, `.sound`).
- DEBUG builds log pending banner ids and fire times via `AppEnvironment.logPlan` (Logger category `app`).

## Gotchas

- A full-screen alert in the plan has no OS notification; if the app is quit or suspended it never shows.
- Full-screen pre-warnings, like every full-screen alert, need the app running.
- Changing a setting reschedules everything; there is no per-alert diffing.

## Tests

- `AlertPlannerTests`: offsets/leads, static time, disabled, titles, horizon, banner cap, bounds, same-instant ids, Bangla titles and ids.
- `AlertSchedulerTests` (fake center and timer): pending set equals plan banners, rebuild merging, tolerance drop, suspend, authorization, failed add.
- `CompositionTests`: default plan is banners only and bounded.

## Debug harness

No dedicated alert harness. Use the overlay harness for full-screen ([overlay.md](overlay.md)); DEBUG logs show the banner plan.
