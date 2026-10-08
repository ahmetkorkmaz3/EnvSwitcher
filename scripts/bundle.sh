#!/bin/sh
# Builds build/EnvSwitcher.app as a universal binary (spec 2026-10-08, section 4.1).
# VERSION sets the version (CI passes it from the tag). Without it, an exact v* tag gives the version,
# or the version is 0.0.0-dev. CODESIGN_IDENTITY names the certificate. Without it, the app gets an
# ad-hoc signature, and the Keychain asks for permission after every build.
set -eu
cd "$(dirname "$0")/.."

if [ -z "${VERSION:-}" ]; then
    TAG="$(git describe --tags --exact-match 2>/dev/null || true)"
    case "$TAG" in
        v[0-9]*) VERSION="${TAG#v}" ;;
        *) VERSION="0.0.0-dev" ;;
    esac
fi
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
IDENTITY="${CODESIGN_IDENTITY:--}"

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
APP="build/EnvSwitcher.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/EnvSwitcher" "$APP/Contents/MacOS/EnvSwitcher"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.ahmetkorkmaz.envswitcher</string>
    <key>CFBundleName</key><string>EnvSwitcher</string>
    <key>CFBundleExecutable</key><string>EnvSwitcher</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Ahmet Korkmaz. MIT License.</string>
</dict>
</plist>
PLIST

if [ "$IDENTITY" = "-" ]; then
    echo "Uyarı: Ad-hoc imza. Keychain her derlemeden sonra izin sorar. Bkz. README → Derleme." >&2
fi
# Hardened runtime now, because notarization needs it later (spec section 9).
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "$APP ($VERSION)"
