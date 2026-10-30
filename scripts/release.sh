#!/usr/bin/env bash
# Builds Meqat as an ad-hoc signed, un-notarized DMG. See docs/release-checklist.md.
# Usage: scripts/release.sh
# Needs no credentials, environment variables or network.
set -euo pipefail

cd "$(dirname "$0")/.."

[[ $# -eq 0 ]] || { echo "usage: scripts/release.sh" >&2; exit 2; }

die() { echo "error: $*" >&2; exit 1; }

VERSION="$(xcodebuild -project Meqat.xcodeproj -scheme Meqat -configuration Release -showBuildSettings 2>/dev/null \
  | awk '/ MARKETING_VERSION /{print $3}')"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "MARKETING_VERSION '$VERSION' is not x.y.z"

OUT=build/release
DMG="$OUT/Meqat-$VERSION.dmg"
rm -rf "$OUT"
mkdir -p "$OUT"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Building Release (ad-hoc signed)"
# Derived data goes to the internal disk: on a non-APFS repo drive, AppleDouble
# (._*) files land inside the bundle and codesign rejects them.
# No entitlements, so no get-task-allow either, and no hardened runtime: it would
# need the location entitlement, and it only matters for notarization.
xcodebuild -project Meqat.xcodeproj -scheme Meqat -configuration Release \
  -derivedDataPath "$STAGE/dd" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGN_ENTITLEMENTS= DEVELOPMENT_TEAM= \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO ENABLE_HARDENED_RUNTIME=NO build
APP="$STAGE/dd/Build/Products/Release/Meqat.app"

[[ -d "$APP" ]] || die "built app not found at $APP"

echo "==> Packaging $DMG"
mkdir "$STAGE/dmg"
cp -R "$APP" "$STAGE/dmg/Meqat.app"
ln -s /Applications "$STAGE/dmg/Applications"
hdiutil create -volname Meqat -srcfolder "$STAGE/dmg" -ov -format UDZO "$DMG"

echo "==> SHA-256"
shasum -a 256 "$DMG"
