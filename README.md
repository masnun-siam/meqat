# Meqat

macOS 14+ menu bar app for prayer times, Jumah, Duha, Tahajjud and the prohibited windows, with a per-event alert (full-screen overlay, banner or nothing). Times come from the [Aladhan API](https://aladhan.com/prayer-times-api) and are cached for offline use.

| Part | Path | What |
|---|---|---|
| MeqatCore | `MeqatCore/` | Swift package with all logic and its XCTest suite |
| Meqat app | `Meqat/`, `Meqat.xcodeproj` | AppKit + SwiftUI menu bar app (scheme `Meqat`) |
| Release | `scripts/release.sh`, `Config/` | Signed, notarized DMG, built on the owner's Mac |

No services, ports or third-party packages.

## Prerequisites

- macOS 14 or later, Xcode 16 or later (CI uses the `macos-15` runner).
- For commits: `brew install pre-commit && pre-commit install`.

## Quickstart

```sh
# Core tests (the live Aladhan test is skipped)
swift test --package-path MeqatCore

# Build the app, unsigned, into build/DerivedData
xcodebuild -project Meqat.xcodeproj -scheme Meqat -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build

# Run it: a text item (next event) appears in the menu bar, no Dock icon
open build/DerivedData/Build/Products/Debug/Meqat.app
```

Quit from the menu bar dropdown.

### Debug harnesses

Debug builds can open one surface with mock data, without location or network:

```sh
open build/DerivedData/Build/Products/Debug/Meqat.app --args -MeqatDebugHarness Overlay
```

Names: `Overlay`, `Menu`, `Settings`, `LoginItem`. See `Meqat/Debug/`.

### Live API tests

```sh
MEQAT_LIVE_TESTS=1 swift test --package-path MeqatCore
```

### Repo on an ExFAT or other non-APFS drive

The volume adds `._*` files to build products and code signing fails (`CodeSign ... ._Resources`). Put build output on the internal disk:

```sh
swift test --package-path MeqatCore --scratch-path "$TMPDIR/meqat-core"
# and for xcodebuild: -derivedDataPath "$TMPDIR/meqat-dd"
```

## Checks

CI (`.github/workflows/ci.yml`) runs on every pull request: the core tests and the unsigned Debug build above. Pre-commit (`.pre-commit-config.yaml`) guards `CLAUDE.md`.

## Install

```sh
brew install masnun-siam/tap/meqat
```

Or download the DMG from the [releases page](https://github.com/masnun-siam/meqat/releases).

## Docs

| Doc | For |
|---|---|
| `CLAUDE.md` | Rules for AI agents (`AGENTS.md` links to it) |
| `docs/guides/meqatcore-conventions.md` | How MeqatCore code is written |
| `docs/guides/app-conventions.md` | How the app target is written |
| `docs/guides/engineering-workflow.md` | Issues, branches, PRs, board |
| `docs/prds/meqat.md` | Product requirements |
| `docs/release-checklist.md` | Release steps and manual checks |
