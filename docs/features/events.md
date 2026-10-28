# Event engine

Covers: MeqatCore/Sources/MeqatCore/Engine/, MeqatCore/Sources/MeqatCore/Settings/{EventID,AppSettings,CalculationMethod,StaticTimeHint,ClockTime}.swift, MeqatCore/Sources/MeqatCore/App/Composition.swift, Meqat/Settings/{EventPane,GeneralPane}.swift, MeqatCore/Tests/MeqatCoreTests/{EventEngineTests,StaticTimeHintTests,CalculationMethodTests,CompositionTests}.swift

Turns one day of cached Aladhan timings plus settings into that day's events as absolute `DateInterval`s. Pure: no I/O, no clock reads. Timings come from [prayer-times-sync](prayer-times-sync.md). Conventions: [meqatcore-conventions](../guides/meqatcore-conventions.md).

## Entry points

- `EventEngine.events(for: LocalDate, cache:, settings:, timeZone:) -> [ScheduledEvent]?` returns nil when the cache has no entry for that date. It passes the previous day's timings (may be nil) to the second overload `events(for:day:previousDay:settings:timeZone:)`.
- `Composition.events(cache:settings:now:timeZone:)` calls it for yesterday through today + 2 (`-1...2`), so a window that began last night and the 48 h alert horizon are covered. No cache gives `[]`.
- Consumers: `Composition.plan` (alerts), menu state (`AppEnvironment.menuState`), and the settings panes (`refreshContext` puts today's `calculatedInterval`s into `SettingsContext.calculatedWindows`).

`ScheduledEvent`: `id`, `date` (the list date it belongs to), `interval` (effective window; nil renders "—" and gets no alerts), `calculatedInterval` (same window with every source calculated), `startsPreviousNight` (true only for a Static Tahajjud placed on the previous date).

## Event set

`EventID` (`Settings/EventID.swift`): `tahajjud, fajr, shuruq, duha, istiwa, dhuhr, jumah, asr, ghurub, maghrib, isha`. A day has 10 events: `jumah` replaces `dhuhr` on Friday (`date.weekday == 6`, Gregorian, 1 = Sunday).

`EventKind`: voluntary = tahajjud, duha; prohibited = shuruq, istiwa, ghurub; obligatory = the rest. Default alert style is `.disabled` for duha and tahajjud, `.banner` for the others (`EventSettings.defaults(for:)`). Display name is the capitalized raw value.

## Calculated windows

Aladhan fields (`DayTimings`): fajr, sunrise, dhuhr, asr, sunset, maghrib, isha, midnight, lastthird. Window lengths come from `GeneralSettings` (`shuruqMinutes` 15, `istiwaMinutes` 10, `ghurubMinutes` 15 by default; each clamped to `Bounds.windowMinutes` = 5...30).

| Event | Start | End |
|---|---|---|
| Tahajjud | previous day's `lastthird` | today's `fajr` |
| Fajr | `fajr` | `sunrise` |
| Shuruq (prohibited) | `sunrise` | `sunrise` + shuruqMinutes |
| Duha | Shuruq end | Istiwa start |
| Istiwa (prohibited) | `dhuhr` - istiwaMinutes | `dhuhr` |
| Dhuhr / Jumah | `dhuhr` | `asr` |
| Asr | `asr` | `sunset` |
| Ghurub (prohibited) | `sunset` - ghurubMinutes | `sunset` |
| Maghrib | `maghrib` | `isha` |
| Isha | `isha` | `midnight` |

Rules:
- Isha ends at Aladhan's `midnight`, which falls on the next date; the event still belongs to today's list (`testIshaEndsAfterMidnightOnNextDate`).
- Aladhan's `lastthird` for day D is the night after D (the live test asserts its date is D + 1), so Tahajjud on D uses D - 1's value. Without D - 1 in the cache, Tahajjud is nil (`testMissingPreviousDayInvalidatesTahajjud`).
- `interval(start:end:)` returns nil when end is not after start, so `DateInterval` never traps. High latitudes can yield empty windows (`testHighLatitudeNeverProducesNonPositiveInterval`).
- Duha is derived from the effective Shuruq end and Istiwa start, so changing those lengths or a Static Shuruq/Istiwa moves Duha.

## Static times

`EventSettings.timeSource`: `.calculated`, or `.fixed` (encoded as `"static"`) with `staticTime: ClockTime` (24 h `HH:mm`). A `.fixed` source without a time behaves as calculated (`testFixedWithoutTimeIsCalculated`). `staticTime` is resolved on the event's date with `matchingPolicy: .nextTime`.

| Event | Effect of Static |
|---|---|
| Shuruq, Istiwa, Ghurub | Static sets the start; the end is start + that window's minutes (duration kept) |
| Fajr, Dhuhr, Jumah, Asr, Maghrib, Isha | Static moves the start only; end stays as calculated (Dhuhr/Jumah still end at `asr`; a start after the end gives nil) |
| Duha | Start follows Shuruq effective end, end follows Istiwa effective start; Duha's own Static is not read for its window |
| Jumah | Uses Jumah's settings on Friday only; Dhuhr's settings apply on other days (`testStaticJumahAppliesOnlyOnFriday`) |
| Tahajjud | Static start, end stays `fajr`; see below |

Static Tahajjud: compare the time to the previous day's Isha clock time. At or after it, the start is on the previous date and `startsPreviousNight` is true; before it, the start is on today's date (after midnight).

Time zone and DST: all conversions use the passed `timeZone` and a Gregorian calendar; `LocalDate` dates are zone-free. On a DST day Aladhan's instants carry the right offset, and a static minute skipped by the change moves to the next valid minute (`testDSTDayUsesNewOffsetAndSkippedMinuteMovesForward`). The time zone is part of the cache identity, so a zone change refetches.

## Calculation method and school

Both only change what is sent to Aladhan (nothing is computed locally):
- `GeneralSettings.method: Int?` (nil = "Automatic (nearest authority)", method param omitted). `CalculationMethod.all` lists 23 ids from Aladhan `/v1/methods`; 6 and 99 (custom) are excluded (`CalculationMethodTests`).
- `GeneralSettings.school: School` (`shafii` = 0, `hanafi` = 1) sent as `school`; it shifts Asr.
- Changing either triggers a debounced sync because `SyncPolicy.needsFetch` compares them with the cached parameters.
- UI: `Meqat/Settings/GeneralPane.swift` (pickers and window-length rows), `EventPane.swift` (per-event source, static time, style).

## Static time hint

`StaticTimeHint.isOutside(_ time:, window:, timeZone:) -> Bool` (`Settings/StaticTimeHint.swift`): resolves `time` on the date the window starts (`.nextTime`) and returns true when it is outside the window; the edges count as inside. Uses the calculated window. Because the time is resolved on the window's start date, a Tahajjud window that starts the previous evening makes any after-midnight static time read as outside (the day-offset is not applied); `testTahajjudAcrossMidnight` only checks a same-day window (02:10-04:30) with 23:30 outside. `EventPane` shows "outside the calculated window" when the check is true; the hint is advisory and never blocks the setting.

## Tests

`EventEngineTests` (set of events, Friday/Thursday, midnight, Tahajjud, each Static case, window lengths, DST, high latitude), `StaticTimeHintTests`, `CalculationMethodTests`, `CompositionTests.testEventsCoverCachedDaysAroundToday` and `testNoCacheMeansNoEventsAndNoAlerts`.
