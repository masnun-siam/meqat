# Release checklist

Signing and notarization run on the owner's Mac, never in CI.

## Owner setup (once)

- [ ] Apple Developer ID Application certificate installed in the login keychain.
- [ ] Notarization credentials stored: `xcrun notarytool store-credentials meqat-notary --apple-id … --team-id …`.
- [ ] Repository `masnun-siam/homebrew-tap` created.

## Each release

1. [ ] Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Meqat.xcodeproj`.
2. [ ] Run `DEVELOPMENT_TEAM=<team id> NOTARY_PROFILE=meqat-notary scripts/release.sh`. It writes `build/release/Meqat-<version>.dmg` and prints its SHA-256. `scripts/release.sh --dry-run` builds an unsigned DMG without credentials.
3. [ ] Check Gatekeeper accepts both, source "Notarized Developer ID":
   - `spctl --assess --type open --context context:primary-signature -v build/release/Meqat-<version>.dmg`
   - `spctl --assess -v /Applications/Meqat.app` (after step 4)
4. [ ] Install the DMG build to `/Applications` and run the manual checklist below.
5. [ ] `gh release create v<version> build/release/Meqat-<version>.dmg`.
6. [ ] Update the cask (below).

## Manual checklist

Run on the notarized build installed to `/Applications`.

- [ ] Overlay over a full-screen Space: trigger an alert while another app is full screen; the overlay covers it.
- [ ] Overlay on two displays: with two displays connected, the overlay shows on both.
- [ ] Hold and dismiss: the overlay holds for its hold time, then dismisses.
- [ ] Sleep across an alert: sleep the Mac before an alert, wake after it; the alert behaves as designed.
- [ ] Permission denied: deny location in System Settings; the app shows its denied state and manual-location path.
- [ ] Launch at login: with the setting on, Meqat is running after a reboot; with it off, it is not (FR-18).
- [ ] No Dock icon: Meqat appears only in the menu bar.
- [ ] Memory under 35 MB: Activity Monitor › Memory column, 10 minutes after launch, before Settings or an overlay has been opened.
- [ ] Overlay replacement: a second alert replaces the overlay shown by the first.
- [ ] Lock screen: lock the Mac across an alert; the alert behaves as designed.
- [ ] Quit before an alert: quit Meqat before an alert time; no alert fires.
- [ ] Return/Esc after the hold: both dismiss the overlay once the hold has ended.
- [ ] Cmd-Tab away from the overlay: the overlay does not break and can still be dismissed.
- [ ] VoiceOver: the overlay announcement and all control labels are read correctly.
- [ ] Text contrast at least 4.5:1 on every gradient (Digital Color Meter or Accessibility Inspector).
- [ ] Reduce Motion: with it on in System Settings, the overlay does not animate.
- [ ] "Settings…" raises the single Settings window on the chosen pane.
- [ ] "Couldn't refresh" shows for 5 s after a failed refresh (turn Wi-Fi off, refresh).
- [ ] Idle Energy Impact averages below 1 in Activity Monitor over 10 idle minutes.
- [ ] Alert fires within 1 s of its time after 30 minutes idle in the background (FR-12).

## Homebrew cask

In `masnun-siam/homebrew-tap`, `Casks/meqat.rb`; each release changes `version` and `sha256`:

```ruby
cask "meqat" do
  version "1.0.0"
  sha256 "<sha256 printed by scripts/release.sh>"

  url "https://github.com/masnun-siam/meqat/releases/download/v#{version}/Meqat-#{version}.dmg"
  name "Meqat"
  desc "Menu bar prayer times, prohibited windows and per-event alerts"
  homepage "https://github.com/masnun-siam/meqat"

  depends_on macos: ">= :sonoma"

  app "Meqat.app"
end
```

Then confirm:

- [ ] `brew audit --cask --strict masnun-siam/tap/meqat`
- [ ] `brew install masnun-siam/tap/meqat`
