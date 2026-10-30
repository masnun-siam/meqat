# Meqat

macOS 14+ menu bar app for prayer times, Jumah, Duha, Tahajjud and the prohibited windows, with a per-event alert (full-screen overlay, banner or nothing). Times come from the [Aladhan API](https://aladhan.com/prayer-times-api) and are cached for offline use.

| Part | Path | What |
|---|---|---|
| MeqatCore | `MeqatCore/` | Swift package with all logic and its XCTest suite |
| Meqat app | `Meqat/`, `Meqat.xcodeproj` | AppKit + SwiftUI menu bar app (scheme `Meqat`) |
| Release | `scripts/release.sh`, `Config/` | Ad-hoc signed, un-notarized DMG, built on the owner's Mac |

No services, ports or third-party packages.

## Prerequisites

- macOS 14 or later, Xcode 26 or later (CI uses the `macos-26` runner; older SDKs report Sendable warnings, which fail the build).
- For commits: `brew install pre-commit && pre-commit install` (installs the pre-commit and pre-push hooks).

## Quickstart

```sh
make help     # list targets
make test     # MeqatCore tests (the live Aladhan test is skipped)
make build    # ad-hoc signed Debug app
make run      # build and launch: a text item (next event) appears in the menu bar, no Dock icon
make check    # lint + test + build, what CI runs
```

Quit from the menu bar dropdown. Build output goes to `$TMPDIR/meqat/<worktree folder>/`, one folder per worktree, so parallel worktrees never share products and a repo on an ExFAT drive still signs. `make clean` removes it. `make format` fixes lint findings.

### Debug harnesses

Debug builds can open one surface with mock data, without location or network:

```sh
make run HARNESS=Overlay   # or Menu, Settings, LoginItem
```

See `Meqat/Debug/`.

### Live API tests

```sh
make test-live
```

## Checks

| Where | What |
|---|---|
| pre-commit | no commits to `main`, gitleaks secret scan, no lint/warning suppressions, `swift format lint --strict`, `CLAUDE.md` guards, YAML/JSON |
| pre-push | `make test` and `make build` when Swift or project files changed |
| CI (`.github/workflows/ci.yml`) | the hooks above on Ubuntu; `make lint test build` on macOS, skipped when only `*.md` or `docs/` changed; `summary` is the required check |
| PR meta (`.github/workflows/pr-meta.yml`) | the PR body references an issue; re-runs on title/body edits |

Warnings are errors in `make test` and `make build`. Formatting rules: `.swift-format`.

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
