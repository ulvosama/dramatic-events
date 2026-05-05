#!/bin/bash
# Build the app and pack it into a distributable .dmg.
# Usage:  ./package-dmg.sh           (uses Info.plist version)
#         ./package-dmg.sh 1.0.1     (override version label)
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Dramatic Events"
APP_BUNDLE="build/$APP_NAME.app"

./build.sh

# Read version from Info.plist (or accept override)
VERSION="${1:-$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
    "$APP_BUNDLE/Contents/Info.plist")}"
# Stable filename so the GitHub "latest release" direct-download URL doesn't
# change between versions:
#   https://github.com/ulvosama/dramatic-events/releases/latest/download/Dramatic-Events.dmg
DMG_NAME="Dramatic-Events.dmg"

echo "▶ Packaging $DMG_NAME"
STAGING="build/dmg-staging"
rm -rf "$STAGING" "build/$DMG_NAME"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "build/$DMG_NAME" >/dev/null

rm -rf "$STAGING"

echo "✓ Built: build/$DMG_NAME (v$VERSION)"
echo
echo "Publish the release with:"
echo "  gh release create v$VERSION 'build/$DMG_NAME' \\"
echo "    --title 'Dramatic Events v$VERSION' \\"
echo "    --notes 'Release notes here.'"
