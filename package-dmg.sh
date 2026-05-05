#!/bin/bash
# Build the .app and pack it into a polished, drag-to-install .dmg.
#
# The DMG window opens with:
#   • Title bar:  "Drag Dramatic Events to Applications →"  (instruction)
#   • Two large icons side-by-side: the .app on the left,
#     a real Applications folder symlink on the right.
#   • No toolbar, no sidebar, no background image.
#
# Usage:  ./package-dmg.sh           (uses Info.plist version for the log line)
#         ./package-dmg.sh 1.1.0     (override version label)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Dramatic Events"
APP_BUNDLE="build/$APP_NAME.app"
VOL_NAME="Drag Dramatic Events to Applications"
DMG_NAME="Dramatic-Events.dmg"
RW_DMG="build/dmg-rw.dmg"
FINAL_DMG="build/$DMG_NAME"

./build.sh

VERSION="${1:-$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
    "$APP_BUNDLE/Contents/Info.plist")}"

# Clean any leftovers from a previous (possibly failed) run.
hdiutil detach "/Volumes/$VOL_NAME" -quiet 2>/dev/null || true
rm -f "$RW_DMG" "$FINAL_DMG"

echo "▶ Creating writable DMG with the .app inside"
hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$APP_BUNDLE" \
    -fs HFS+ \
    -format UDRW \
    -size 50m \
    -ov \
    "$RW_DMG" >/dev/null

echo "▶ Mounting"
MOUNT_POINT=$(hdiutil attach -readwrite -noautoopen -noverify "$RW_DMG" \
    | awk '/Apple_HFS/ {for (i=3; i<=NF; i++) printf "%s ", $i; print ""}' \
    | sed 's/ *$//')

if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
    echo "✗ Could not determine mount point" >&2
    exit 1
fi

echo "▶ Adding Applications symlink"
ln -s /Applications "$MOUNT_POINT/Applications"

echo "▶ Styling Finder window (this may prompt for Automation permission once)"
osascript - "$VOL_NAME" "$APP_NAME" <<'APPLESCRIPT' >/dev/null
on run argv
    set volName to item 1 of argv
    set appName to item 2 of argv
    set appItemName to appName & ".app"
    tell application "Finder"
        tell disk volName
            open
            tell container window
                set current view to icon view
                set toolbar visible to false
                set statusbar visible to false
                set the bounds to {200, 200, 1000, 700}
            end tell
            set theViewOptions to the icon view options of container window
            set arrangement of theViewOptions to not arranged
            set icon size of theViewOptions to 192
            set text size of theViewOptions to 14
            set position of item appItemName of container window to {220, 230}
            set position of item "Applications" of container window to {620, 230}
            update without registering applications
            delay 2
            close
        end tell
    end tell
end run
APPLESCRIPT

# Make sure the .DS_Store written by Finder is flushed before we detach.
sync
sleep 1

echo "▶ Detaching"
hdiutil detach "$MOUNT_POINT" -quiet

echo "▶ Converting to compressed read-only DMG"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null
rm -f "$RW_DMG"

echo "✓ Built: $FINAL_DMG (v$VERSION)"
echo
echo "Publish the release with:"
echo "  gh release create v$VERSION '$FINAL_DMG' \\"
echo "    --title 'Dramatic Events v$VERSION' \\"
echo "    --notes 'Release notes here.'"
