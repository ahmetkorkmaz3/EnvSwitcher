#!/bin/sh
# Builds build/EnvSwitcher.app. Set CODESIGN_IDENTITY to sign with your own certificate
# (spec 2.2). Without it, the app gets an ad-hoc signature.
set -eu
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/EnvSwitcher.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/EnvSwitcher" "$APP/Contents/MacOS/EnvSwitcher"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.ahmetkorkmaz.envswitcher</string>
    <key>CFBundleName</key><string>EnvSwitcher</string>
    <key>CFBundleExecutable</key><string>EnvSwitcher</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign "${CODESIGN_IDENTITY:--}" "$APP"
echo "$APP"
