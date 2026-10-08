#!/bin/sh
# Builds Resources/AppIcon.icns from scripts/make-icon.swift (spec 2026-10-08, section 4.2).
set -eu
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift scripts/make-icon.swift "$WORK/icon-1024.png"
ICONSET="$WORK/AppIcon.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
    double=$((size * 2))
    sips -z "$size" "$size" "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$double" "$double" "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
mkdir -p Resources
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo Resources/AppIcon.icns
