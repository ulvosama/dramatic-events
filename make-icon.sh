#!/bin/bash
# Generates AppIcon.icns from app-icon.png using sips + iconutil (built into macOS).
set -euo pipefail
cd "$(dirname "$0")"

SRC="app-icon.png"
ICONSET="DramaticEvents/AppIcon.iconset"
OUT="DramaticEvents/AppIcon.icns"

if [[ ! -f "$SRC" ]]; then
    echo "✗ Source $SRC not found." >&2
    exit 1
fi

echo "▶ Generating iconset from $SRC"
rm -rf "$ICONSET" "$OUT"
mkdir -p "$ICONSET"

declare -a SIZES=(
    "16   icon_16x16.png"
    "32   icon_16x16@2x.png"
    "32   icon_32x32.png"
    "64   icon_32x32@2x.png"
    "128  icon_128x128.png"
    "256  icon_128x128@2x.png"
    "256  icon_256x256.png"
    "512  icon_256x256@2x.png"
    "512  icon_512x512.png"
    "1024 icon_512x512@2x.png"
)

for entry in "${SIZES[@]}"; do
    size=$(echo "$entry" | awk '{print $1}')
    name=$(echo "$entry" | awk '{print $2}')
    sips -z "$size" "$size" "$SRC" --out "$ICONSET/$name" >/dev/null
done

echo "▶ Converting to .icns"
iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$ICONSET"

echo "✓ $OUT"
