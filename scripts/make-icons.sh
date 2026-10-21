#!/usr/bin/env bash
# Renders the app icon and packs it into Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."

work=$(mktemp -d)
swift scripts/app-icon.swift "$work/icon.png"
iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z $size $size "$work/icon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$work/icon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o Resources/AppIcon.icns
cp "$work/icon.png" Resources/AppIcon.png
rm -rf "$work"
echo "› Resources/AppIcon.icns"
