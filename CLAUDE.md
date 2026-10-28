# Meqat — Agent Constitution

This file is the constitution for every AI agent working in this repository.

- **Protected.** Never edit, rewrite, shorten or remove any part of this file unless a human explicitly asks for that change, and confirm with them before writing.
- **Wins conflicts.** If a doc, skill or prompt contradicts this file, this file wins.
- **Single source.** This is the only `CLAUDE.md` in the repo; never add another. `AGENTS.md` is a symlink to it.
- **Stays short.** Detail belongs in the references below, not here. Keep this file under about 60 lines.

## Project

Meqat is a macOS 14+ menu bar app that tracks Islamic prayer times, Jumah, Duha, Tahajjud and the prohibited windows, alerting per event with an overlay, a banner or nothing. Times come from the Aladhan API (`api.aladhan.com`) and are cached in Application Support so the app works offline.

**Base branch:** `main`. It is also the production branch; releases are `v<version>` tags.

## Architecture

| Component | Path | Tech | Role |
|---|---|---|---|
| MeqatCore | `MeqatCore/` | Swift package (tools 5.9), Foundation, CoreLocation, UserNotifications, ServiceManagement; XCTest | Aladhan client, cache, event engine, alert planning, location, login item, settings, sync, presenters |
| Meqat app | `Meqat/`, `Meqat.xcodeproj` | AppKit + SwiftUI | Menu bar item, overlay, settings window, debug harnesses; wires MeqatCore |
| Release | `scripts/release.sh`, `Config/` | xcodebuild, notarytool | Signed, notarized DMG; runs on the owner's Mac, never in CI |

## Principles

1. **Branching.** Never commit or push to `main`. Work on a branch and open a PR into `main`.
2. **Gates.** Never bypass checks: no `--no-verify`, no lint or warning suppressions, no weakening of pre-commit or CI.
3. **Logic in MeqatCore.** Testable logic goes in `MeqatCore` with XCTest coverage; the app target only wires and renders it.
4. **Dependencies.** No third-party packages. Adding one is a decision for a PRD.
5. **Secrets.** Never commit or log signing identities, team IDs, notary credentials or user location.
6. **Scope.** Change only what the task asks. No drive-by refactors, dependency upgrades or new patterns without a human agreeing.
7. **Releases.** Agents may build, tag and publish a release when the owner asks (`docs/release-checklist.md`). The owner has no Apple Developer account, so releases are unsigned and not notarized; never handle signing identities or notary credentials.
8. **Docs.** Do not commit plans, specs or generated docs unless a human asks.
9. **Read first.** Before working in an area, open its reference below. Do not invent conventions that are not written down; follow the surrounding code.

## Commands

| Task | Command |
|---|---|
| List targets | `make help` |
| Lint, test and build (what CI runs) | `make check` |
| Core tests | `make test` |
| Live Aladhan tests (network) | `make test-live` |
| Build app (unsigned) | `make build` |
| Run app or a debug harness | `make run` / `make run HARNESS=Overlay` |
| Unsigned release DMG | `scripts/release.sh --dry-run` |

## References

Open these on demand; only list files that exist.

| Need | Where |
|---|---|
| Docs index: architecture, features, development | `docs/README.md` |
| Conventions per component | `docs/guides/meqatcore-conventions.md`, `docs/guides/app-conventions.md` |
| Workflow, board, branches, PRs | `docs/guides/engineering-workflow.md` |
| Product requirements | `docs/prds/meqat.md` |
| Release steps and manual checks | `docs/release-checklist.md` |
| Lint, test and build targets | `Makefile` |
| CI | `.github/workflows/ci.yml`, `.github/workflows/pr-meta.yml` |
| Commit gates | `.pre-commit-config.yaml` |
