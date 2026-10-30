---
name: release
description: Cut a Meqat release end to end - version bump PR, unsigned DMG, GitHub release, Homebrew cask. Use when the owner says /release, "make a release", "publish it" or "update the cask".
---

# Release

Unsigned, not notarized (CLAUDE.md rule 7; there is no Apple Developer account). Never touch signing identities or notary credentials. Never push to `main`; agents never merge PRs, so the owner merges the bump PR. Argument: the version, e.g. `1.2.0`; if absent, propose one from `git log <last tag>..origin/main` (minor for features, patch for fixes) and confirm.

Run from the repo root. Work out which phase applies from `git tag`, `gh pr list --search "bump version"` and the tap.

## Phase 1 - bump PR

1. `git fetch origin`, `git switch -c release-<v> origin/main`.
2. In `Meqat.xcodeproj/project.pbxproj` set every `MARKETING_VERSION = <v>;` and add 1 to every `CURRENT_PROJECT_VERSION`.
3. `make check` must pass, then `scripts/release.sh --dry-run` must end with a DMG and SHA-256.
4. Commit `chore: bump version to <v>`, push, open a PR into `main` listing the merged PRs since the last tag. Stop and ask the owner to merge it.

## Phase 2 - publish (after the bump PR is merged)

1. `git fetch origin && git switch --detach origin/main`; confirm `MARKETING_VERSION` is `<v>` and `git tag -l v<v>` is empty.
2. `scripts/release.sh --dry-run`; note the SHA-256 of `build/release/Meqat-<v>.dmg`.
3. `gh release create v<v> build/release/Meqat-<v>.dmg --target "$(git rev-parse HEAD)" --title "Meqat <v>" --notes "<changes, PR numbers>

Unsigned, not notarized: right-click the app and choose Open the first time.

SHA-256: <sha>"` (this creates the tag on the remote; do not push to `main`).
4. Verify: `gh release download v<v> -p '*.dmg' -O - | shasum -a 256` equals the noted SHA-256.

## Phase 3 - Homebrew cask

1. `gh repo clone masnun-siam/homebrew-tap "$(mktemp -d)/tap"`; use `mktemp`, never `rm -r` (a hook blocks it).
2. In `Casks/meqat.rb` set `version "<v>"` and `sha256 "<sha>"`; leave the rest, including the quarantine caveats.
3. Commit `meqat <v>`, push to the tap's `main`, then read the file back through `gh api` to confirm.

## Report

One short message: release URL, SHA-256, tap commit. State what was not checked (manual checklist in `docs/release-checklist.md`, `brew audit`, `brew install`); Gatekeeper checks do not apply to an unsigned build.
