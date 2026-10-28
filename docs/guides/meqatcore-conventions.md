# MeqatCore conventions

Read before changing `MeqatCore/`. Every rule names the file that sets the pattern; exceptions are listed. Run tests with `swift test --package-path MeqatCore`.

## Layout

| Rule | Set by |
|---|---|
| One folder per concern under `Sources/MeqatCore/`: `Aladhan`, `Alerts`, `App`, `Cache`, `Engine`, `Location`, `LoginItem`, `Menu`, `Overlay`, `Settings`, `Sync` | `Package.swift` (single target, no third-party deps) |
| One primary type per file, file named after it | `Alerts/AlertScheduler.swift`, `Cache/CacheStore.swift` |
| Protocol seam lives next to its consumer, in its own file when small | `Aladhan/HTTPTransport.swift`, `Alerts/NotificationCentering.swift`, `Alerts/AlertTimer.swift` |
| Cross-concern glue goes in `App/Composition.swift` (stateless `enum` plus extensions) | `Composition`, `MenuSyncInfo.init(_ status:)` |
| Exceptions: value types and enums of one concern may share a file (`Cache/LocalDate.swift` has `LocalDate` and `YearMonth`; `Cache/TimingsCache.swift` has five types; `Alerts/AlertPlanner.swift` has `AlertKind` and `PlannedAlert`). `FetchParameters.current(...)` lives in `Sync/SyncPolicy.swift`, not in `Cache/` |
| Shared constants: `MeqatCore.bundleIdentifier` (`MeqatCore.swift`) is the `Logger` subsystem | `Sync/SyncCoordinator.swift` |

## Types: value vs reference

| Kind | Use | Example |
|---|---|---|
| Stateless logic | caseless `enum` with `static` funcs | `EventEngine`, `AlertPlanner`, `MenuPresenter`, `SyncPolicy`, `LoginItemSync`, `Composition`, `ManualCityInput`, `StaticTimeHint` |
| Data | `struct`/`enum`, `Equatable, Sendable` | `ScheduledEvent`, `PlannedAlert`, `MenuInput`, `MenuState`, `SyncStatus` |
| Persisted data | add `Codable` | `Settings/AppSettings.swift`, `TimingsCache` |
| Stateful, UI-observed | `@MainActor @Observable public final class` | `SyncCoordinator`, `AlertScheduler`, `LocationProvider`, `SettingsStore` |
| Small value with mutation | `struct` with `mutating` funcs and the instant passed in | `Overlay/OverlayHold.swift` (not `Sendable`-declared) |
| Non-actor class with no mutable state | `final class ... : Sendable` | `Cache/CacheStore.swift` |
| Non-actor class with mutable state, main-queue only | `final class` implementing an `AnyObject` protocol, no `Sendable` | `DispatchAlertTimer`, `MainAppLoginItem` |

- Pure types do no I/O and no clock reads; the doc comment says so (`EventEngine`, `MenuPresenter`, `MenuInput`). Callers pass `now` and `timeZone`.
- Every public data type is `Sendable`. Exception: `OverlayHold` (`Equatable` only).
- Result structs have `public let` fields (`MenuState`, `MenuRow`, `PlannedAlert`). Input/settings structs have `public var` fields and an explicit `public init` (`MenuInput`, `FetchParameters`). Exception: `MenuState`, `MenuRow` and `PlannedAlert` have no public init (built only inside the package; tests use `@testable`).
- `@unchecked Sendable` appears only in test fakes, never in `Sources/`.

## Dependency injection

Inject through `init` with production defaults. No singletons, no global mutable state.

| Dependency | Injection | Set by |
|---|---|---|
| HTTP | `HTTPTransport` protocol, default `URLSessionTransport()` | `AladhanClient.init` |
| Fetching | `AladhanFetching` protocol (what `SyncCoordinator` takes, not the concrete client) | `Sync/SyncCoordinator.swift` |
| Notifications | `NotificationCentering`; `UNUserNotificationCenter` conforms by extension | `Alerts/NotificationCentering.swift` |
| Timer | `AlertTimer` protocol, handler is `@MainActor` | `Alerts/AlertTimer.swift` |
| CoreLocation | `LocationManaging`; `CLLocationManager` conforms by extension | `Location/LocationProvider.swift` |
| Login item | `LoginItemService` | `LoginItem/LoginItemSync.swift` |
| Clock | `now: @Sendable () -> Date`, default `Date.init` or `{ Date() }` | `SyncCoordinator`, `AlertScheduler`, `LocationProvider` |
| Time zone | `timeZone: @Sendable () -> TimeZone`, default `{ .current }` | `SyncCoordinator`, `AlertScheduler` |
| Sleep | `sleep: @Sendable (Duration) async throws -> Void`, default `{ try await Task.sleep(for: $0) }` | `SyncCoordinator`, `LocationProvider` |
| Live inputs | `@MainActor () -> T` closures (`parameters`, `plan`) so the owner is not captured | `SyncCoordinator.init`, `AlertScheduler.init` |
| Storage | `CacheStore(directory:)`, `SettingsStore(defaults:)` | `Cache/CacheStore.swift`, `Settings/SettingsStore.swift` |

- Wrap only the slice of a system type you use (`LocationManaging` lists 5 members). Conform the system type with `extension X: Protocol {}`.
- Exception: `AlertScheduler.init` has no default for `center`, `timer` or `plan` (the app supplies them).
- Exception: `LoginItemSync.apply` takes the service as a parameter instead of init.

## Concurrency

- Async only where there is I/O or waiting: `HTTPTransport.data`, `AladhanFetching.fetchMonth`, `NotificationCentering.add`. No `DispatchQueue` except `DispatchAlertTimer`, which needs a strict wall-clock source.
- Observable classes mark `@MainActor @Observable`. Non-UI state is `@ObservationIgnored private`; only `private(set) public` state that views read is observed. Callbacks (`onChange`, `onCacheReplaced`, `onFullScreen`) are `@ObservationIgnored public var`, optional closures.
- Tasks: store handles (`syncTask`, `waitTask`, `debounceTask`, `fixTimer`), cancel before replacing, and `guard !Task.isCancelled` after a sleep (`SyncCoordinator.trigger`, `scheduleRetry`).
- Capture the injected closure into the task (`Task { [sleep] in ... }`) as `SyncCoordinator` and `LocationProvider` do.
- Delegate callbacks from system frameworks are `nonisolated` and hop with `Task { @MainActor in ... }` (`LocationProvider` delegate methods). Handlers they call are internal (`handleAuthorization`, `handleLocations`, `handleFailure`) so tests call them directly.
- Overlapping work coalesces with a pending flag, not a queue: `AlertScheduler.rebuildPending`, `SyncCoordinator.followUpPending`.
- Timer handler bridges with `MainActor.assumeIsolated` (`DispatchAlertTimer.arm`), valid because the source runs on `.main`.

## Errors and logging

| Rule | Set by |
|---|---|
| Domain errors are an `Error, Equatable` enum with payload only for ints and short strings | `Aladhan/AladhanError.swift` |
| Validate untrusted input and throw the typed error: body size cap, `code == 200`, date inside the month, no duplicate date | `AladhanClient.parse` |
| Do not surface raw errors to the UI. Map to a small enum in `Sendable` form | `SyncFailure` (`Sync/SyncStatus.swift`) then `MenuFailure` (`App/Composition.swift`) |
| Failures with a fallback are swallowed with `try?` or logged, not thrown: corrupt cache is deleted and returns `nil` | `CacheStore.load` |
| A thrown save error is logged, not rethrown, in the coordinator | `SyncCoordinator.clearCachedLocation` |
| Return the error instead of throwing when the caller only reports it | `LoginItemSync.apply` (`@discardableResult`) |
| Logging uses `os.Logger(subsystem: MeqatCore.bundleIdentifier, category:)` with `privacy: .public` only on error kinds | `SyncCoordinator.kind(of:)` logs kind only, never URL, coordinates or place name |
| No `print`, no `fatalError`. Force-unwraps are reserved for values that cannot fail (`TimeZone(identifier: "UTC")!`, `Calendar.date(from:)!` in `LocalDate`) | `Cache/LocalDate.swift` |

## Time zones and local dates

- Calendar days are `LocalDate` / `YearMonth`, never `Date` ranges (`Cache/LocalDate.swift`). Make one with `LocalDate(date, timeZone:)`.
- Date arithmetic goes through `LocalDate.adding(days:)` (UTC noon, DST-safe). Weekday uses `LocalDate.weekday` (6 is Friday, used by `EventEngine` for Jumah).
- Every `Calendar` is `Calendar(identifier: .gregorian)` with `timeZone` set from the injected zone. Never read `.current` inside a pure type; only init defaults do (`{ .current }`).
- Every `DateFormatter` sets `locale = en_US_POSIX` and `timeZone` (`MenuPresenter.Formatters`, `AlertPlanner.plan`).
- Resolve a wall-clock time with `matchingPolicy: .nextTime` so DST gaps move forward (`EventEngine.resolve`, `StaticTimeHint`).
- `DateInterval` traps on end < start. Build through the guarded helper that returns `nil` (`EventEngine.interval(start:end:)`); `nil` interval means "no window", rendered "—".
- API timings are ISO 8601 instants (`iso8601=true`); store `Date`, not strings (`AladhanClient.parse`, `DayTimings`).
- Cache covers yesterday through today + 30 days (`SyncPolicy.months`, `needsFetch`); events cover yesterday through today + 2 (`Composition.events`).

## Persistence

| Store | Rule | Set by |
|---|---|---|
| `CacheStore` | One file `timings.json` in `directory`; `.atomic` writes; `sortedKeys`; `.iso8601` dates; wrong `formatVersion` or undecodable file is deleted | `Cache/CacheStore.swift` |
| `TimingsCache` | Hand-written `Codable`: flat keys, explicit `null`, days sorted by date. Bump `currentFormatVersion` when the layout changes | `Cache/TimingsCache.swift` |
| `SettingsStore` | `UserDefaults` with three groups (`settings.general`, `.location`, `.events`), each wrapped in `Envelope(version:value:)`. Only groups that changed are written. `onChange(old, new)` fires after save | `Settings/SettingsStore.swift` |
| Settings types | Tolerant decode: `decodeIfPresent ... ?? default`; unknown or missing events fall back to `EventSettings.defaults(for:)`; numeric fields clamp via `Bounds.clamped` in `init` and `didSet` | `Settings/AppSettings.swift` (`EventsGroup`, `StartAlert`) |
| Custom wire format | String codecs validate strictly and throw `DecodingError.dataCorrupted`: `"HH:mm"`, `"yyyy-MM-dd"` | `Settings/ClockTime.swift`, `LocalDate` |

- Mutate settings through `SettingsStore` helpers (`setLocationMode`, `setManualLocation`, `resetEvent`, `resetAll`), not by editing `settings` field by field in feature code.
- `CacheStore.defaultDirectory()` is the only place that resolves `applicationSupportDirectory`.

## Access control and naming

- `public` on every type, member and init the app target uses; internal for helpers and test seams (`handleLocations`, `AladhanClient.request(for:parameters:)`, `EventSettings.init(from:id:)`, `static let backoff`). Tests reach internals with `@testable import`.
- Constants are `static let` on the owning type with units in the name or type: `Duration` (`SyncCoordinator.backoff`, `fixTimeout`), `TimeInterval` (`AlertPlanner.horizon`, `AlertScheduler.lateTolerance`), `...Meters`, `...Minutes`, `...Seconds`.
- Names: `...Provider`, `...Coordinator`, `...Scheduler` for stateful classes; `...Planner`, `...Presenter`, `...Engine`, `...Policy` for pure enums; protocols are capabilities (`NotificationCentering`, `LocationManaging`, `AladhanFetching`) or roles (`HTTPTransport`, `AlertTimer`, `LoginItemService`).
- Enum raw values equal wire values; use a case name with `= "static"` when the Swift keyword is reserved (`TimeSource.fixed`).
- Alert ids are `<yyyy-MM-dd>.<eventID>.<kind>` (`PlannedAlert.id`).
- Doc comments (`///`) state invariants and nil meaning (`FetchParameters.location`, `ScheduledEvent.interval`). `// MARK:` sections split long files (`AladhanClient`, `SyncCoordinator`).
- Domain order is fixed: `EventID.allCases` (tahajjud ... isha). `EventEngine` emits 10 events, `.jumah` replacing `.dhuhr` on Friday.

## Tests

Layout: `Tests/MeqatCoreTests/<Type>Tests.swift` per source type, XCTest, `@testable import MeqatCore`. Shared helpers in `Support/`; JSON in `Fixtures/` (copied as a resource in `Package.swift`).

| Need | Use | File |
|---|---|---|
| Load a JSON fixture | `try Fixture.data("engine/name.json")` (path under `Fixtures/`) | `Support/Fixture.swift` |
| Decode a cache fixture | `JSONDecoder` with `.iso8601` then `TimingsCache` | `EventEngineTests.swift`, `CompositionTests.swift` |
| Fake the clock for sleep | `ManualSleeper` actor: `sleep` suspends, `advance(by:)` releases, `requestedDurations` asserts delays | `Support/ManualSleeper.swift`, `SyncCoordinatorTests.swift` |
| Fake the Aladhan client | `StubAladhan` actor: `calls`, `fail(with:)`, `hold()`/`release()`, `day(_:)`, `days(in:)` | `Support/StubAladhan.swift` |
| Fake HTTP | `StubTransport` (records `requests`) | `AladhanClientTests.swift` (file-local) |
| Fake notifications and timer | `FakeNotificationCenter`, `FakeAlertTimer` | `AlertSchedulerTests.swift` (file-local) |
| Fake CoreLocation | `FakeLocationManager`, `FakeSleeper`, `Clock` (`private`) | `LocationProviderTests.swift` |
| Fake login item | `FakeLoginItem` (`private`) | `LoginItemSyncTests.swift` |
| Isolated disk | `FileManager.default.temporaryDirectory/<UUID>` removed in `tearDown` | `TimingsCacheTests.swift`, `SyncCoordinatorTests.swift` |
| Isolated defaults | `UserDefaults(suiteName: UUID)` then `removePersistentDomain` | `SettingsTests.swift` |

- Mark a test class `@MainActor` iff it drives a `@MainActor` type (`SyncCoordinatorTests`, `AlertSchedulerTests`, `LocationProviderTests`, `SettingsTests`). Pure-type tests are plain `final class`.
- Pin zones and instants: `TimeZone(identifier:)` literals (`Asia/Dhaka`, `America/New_York`, `UTC`) and fixed epoch seconds with a comment (`oct15 = ... // 2026-10-15 12:00 UTC`). Never `Date()`.
- Cross a clock into a `@Sendable` closure through a small `@unchecked Sendable` box or a captured `let` (`Clock` in `LocationProviderTests`, `let date = now!` in `SyncCoordinatorTests`).
- Async settling: `eventually { ... }` polling (`SyncCoordinatorTests`) or `for _ in 0..<50 { await Task.yield() }` (`AlertSchedulerTests.rebuild`). No fixed sleeps for correctness.
- Names are `test<Behavior>` sentences (`testFridayHasTenEventsInOrderWithJumah`). Test helpers are `private` and take `file: StaticString = #filePath, line: UInt = #line` when they assert (`assertInvalid`, `eventually`).
- Live network tests start with `try XCTSkipUnless(ProcessInfo.processInfo.environment["MEQAT_LIVE_TESTS"] == "1")`. Run with `MEQAT_LIVE_TESTS=1 swift test --package-path MeqatCore`. Only `AladhanLiveTests.swift` does this.
- Exceptions: `LocationProviderTests` has its own `FakeSleeper` instead of `ManualSleeper`; fixtures are used only by Aladhan, engine and composition tests; presenter/planner tests build data in code (`MenuPresenterTests.mockup`).
- `SmokeTests` only checks `MeqatCore.bundleIdentifier`.
- Exception: `StaticTimeHintTests.swift` uses Swift Testing (`import Testing`, `@Suite`, `@Test`) instead of XCTest; it is the only one. New tests follow XCTest.

## Adding a feature

1. Pick the concern folder in `Sources/MeqatCore/`; create a new one only for a new concern.
2. Put logic in a pure `enum` (inputs: values, `now`, `timeZone`) or, if it holds state, a `@MainActor @Observable final class` with injected `now`/`sleep`/protocols and production defaults.
3. Wrap each new system API in a minimal protocol in its own file; conform the real type by extension; keep it `public`.
4. Add settings fields with a default, a `Bounds` clamp if numeric, and tolerant `decodeIfPresent` decoding; bump the `Envelope` version only for incompatible changes.
5. Map new failures to a small `Sendable` enum before they reach `Menu*` types; log kind only.
6. Wire new pieces in `App/Composition.swift` if they join stores, engine, planner or menu.
7. Add `Tests/MeqatCoreTests/<Type>Tests.swift` with fakes from `Support/` (add new shared fakes there; keep one-off fakes `private` in the test file). Add JSON under `Fixtures/<area>/` for real API or cache shapes.
8. Run `swift test --package-path MeqatCore`; run with `MEQAT_LIVE_TESTS=1` when touching `Aladhan/`.
