#!/usr/bin/env bash
# Builds, signs, notarizes and packages Meqat as a DMG. See docs/release-checklist.md.
# Usage: scripts/release.sh [--dry-run]
#   --dry-run  unsigned Release build and DMG; needs no credentials or network.
# Env (full run only): DEVELOPMENT_TEAM, NOTARY_PROFILE.
set -euo pipefail

cd "$(dirname "$0")/.."

DRY_RUN=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  *) echo "usage: scripts/release.sh [--dry-run]" >&2; exit 2 ;;
esac

die() { echo "error: $*" >&2; exit 1; }

if [[ $DRY_RUN -eq 0 ]]; then
  [[ -n "${DEVELOPMENT_TEAM:-}" ]] || die "DEVELOPMENT_TEAM is not set (your Apple Developer team ID)"
  [[ -n "${NOTARY_PROFILE:-}" ]] || die "NOTARY_PROFILE is not set. Create one with: xcrun notarytool store-credentials meqat-notary --apple-id … --team-id …"
fi

VERSION="$(xcodebuild -project Meqat.xcodeproj -scheme Meqat -configuration Release -showBuildSettings 2>/dev/null \
  | awk '/ MARKETING_VERSION /{print $3}')"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "MARKETING_VERSION '$VERSION' is not x.y.z"

OUT=build/release
DMG="$OUT/Meqat-$VERSION.dmg"
rm -rf "$OUT"
mkdir -p "$OUT"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

if [[ $DRY_RUN -eq 1 ]]; then
  echo "==> Building Release (unsigned)"
  xcodebuild -project Meqat.xcodeproj -scheme Meqat -configuration Release \
    -derivedDataPath "$OUT/dd" CODE_SIGNING_ALLOWED=NO build
  APP="$OUT/dd/Build/Products/Release/Meqat.app"
else
  echo "==> Archiving"
  xcodebuild -project Meqat.xcodeproj -scheme Meqat -configuration Release \
    -archivePath "$OUT/Meqat.xcarchive" DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" archive

  echo "==> Exporting"
  OPTIONS="$STAGE/ExportOptions.plist"
  cp Config/ExportOptions.plist "$OPTIONS"
  /usr/libexec/PlistBuddy -c "Set :teamID $DEVELOPMENT_TEAM" "$OPTIONS"
  xcodebuild -exportArchive -archivePath "$OUT/Meqat.xcarchive" \
    -exportOptionsPlist "$OPTIONS" -exportPath "$OUT/export"
  APP="$OUT/export/Meqat.app"
fi

[[ -d "$APP" ]] || die "built app not found at $APP"

echo "==> Packaging $DMG"
mkdir "$STAGE/dmg"
cp -R "$APP" "$STAGE/dmg/Meqat.app"
ln -s /Applications "$STAGE/dmg/Applications"
hdiutil create -volname Meqat -srcfolder "$STAGE/dmg" -ov -format UDZO "$DMG"

if [[ $DRY_RUN -eq 0 ]]; then
  echo "==> Signing DMG"
  codesign --sign "Developer ID Application" --timestamp "$DMG"

  echo "==> Notarizing (waits for Apple)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait \
    || die "notarization failed; inspect with: xcrun notarytool log <submission id> --keychain-profile \"\$NOTARY_PROFILE\""

  echo "==> Stapling"
  xcrun stapler staple "$DMG"
fi

echo "==> SHA-256"
shasum -a 256 "$DMG"
