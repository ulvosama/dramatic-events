#!/bin/bash
# Build "Dramatic Events.app" from source — no Xcode project needed.
set -euo pipefail

cd "$(dirname "$0")"

SRC_DIR="DramaticEvents"
BIN_NAME="DramaticEvents"          # CFBundleExecutable
APP_NAME="Dramatic Events"          # User-facing display name
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# Generate the icon if it's missing or older than the source PNG.
if [[ ! -f "$SRC_DIR/AppIcon.icns" || "app-icon.png" -nt "$SRC_DIR/AppIcon.icns" ]]; then
    ./make-icon.sh
fi

echo "▶ Cleaning $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS" "$RESOURCES"

echo "▶ Compiling Swift sources"
xcrun -sdk macosx swiftc \
    -target arm64-apple-macos14.0 \
    -swift-version 5 \
    -O \
    -o "$MACOS/$BIN_NAME" \
    "$SRC_DIR/main.swift" \
    "$SRC_DIR/Settings.swift" \
    "$SRC_DIR/LoginItemHelper.swift" \
    "$SRC_DIR/UpdateChecker.swift" \
    "$SRC_DIR/NotificationManager.swift" \
    "$SRC_DIR/WelcomeWindowController.swift" \
    "$SRC_DIR/SettingsWindowController.swift" \
    "$SRC_DIR/EventLinkParser.swift" \
    "$SRC_DIR/AppDelegate.swift" \
    "$SRC_DIR/StatusItemManager.swift" \
    "$SRC_DIR/CalendarManager.swift" \
    "$SRC_DIR/MeetingPresenceDetector.swift" \
    "$SRC_DIR/SoundPlayer.swift"

echo "▶ Copying Info.plist + resources"
cp "$SRC_DIR/Info.plist"          "$CONTENTS/Info.plist"
cp "$SRC_DIR/bbc_news_theme.mp3"  "$RESOURCES/bbc_news_theme.mp3"
cp "$SRC_DIR/AppIcon.icns"        "$RESOURCES/AppIcon.icns"

echo "▶ Ad-hoc signing with entitlements"
codesign --force --deep \
    --sign - \
    --entitlements "$SRC_DIR/DramaticEvents.entitlements" \
    "$APP_BUNDLE"

echo "✓ Built: $APP_BUNDLE"
echo
echo "Run with:  open '$APP_BUNDLE'"
