#!/bin/sh
# Installs or updates EnvSwitcher from GitHub Releases (spec 2026-10-08, section 6).
#   curl -fsSL https://raw.githubusercontent.com/ahmetkorkmaz3/env-management/main/install.sh | sh
# ENVSWITCHER_VERSION=0.2.0 installs that version.
# ENVSWITCHER_DOWNLOAD_BASE and ENVSWITCHER_INSTALL_DIR are for tests only.
set -eu

REPO="ahmetkorkmaz3/env-management"
APP_NAME="EnvSwitcher"
DEST_DIR="${ENVSWITCHER_INSTALL_DIR:-/Applications}"

fail() { printf 'Hata: %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "EnvSwitcher yalnızca macOS üzerinde çalışır."
MACOS="$(sw_vers -productVersion)"
[ "${MACOS%%.*}" -ge 14 ] || fail "EnvSwitcher macOS 14 veya üstünü ister. Bu Mac: macOS $MACOS."

if [ -n "${ENVSWITCHER_VERSION:-}" ]; then
    VERSION="${ENVSWITCHER_VERSION#v}"
else
    # The redirect of /releases/latest names the tag. It has no API rate limit.
    LATEST="https://github.com/$REPO/releases/latest"
    URL="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$LATEST")" \
        || fail "Son sürüm okunamadı: $LATEST. İnternet bağlantısını kontrol edin ve komutu yeniden çalıştırın."
    case "$URL" in
        */tag/v*) VERSION="${URL##*/tag/v}" ;;
        *) fail "Henüz bir sürüm yayınlanmadı: $LATEST" ;;
    esac
fi
case "$VERSION" in
    "" | *[!0-9.]*) fail "Geçersiz sürüm: \"$VERSION\". Örnek: ENVSWITCHER_VERSION=0.2.0" ;;
esac

ZIP="$APP_NAME-$VERSION.zip"
BASE="${ENVSWITCHER_DOWNLOAD_BASE:-https://github.com/$REPO/releases/download/v$VERSION}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "EnvSwitcher $VERSION indiriliyor..."
for FILE in "$ZIP" "$ZIP.sha256"; do
    curl -fsSL -o "$WORK/$FILE" "$BASE/$FILE" \
        || fail "İndirme başarısız: $BASE/$FILE. İnternet bağlantısını kontrol edin ve komutu yeniden çalıştırın."
done
(cd "$WORK" && shasum -a 256 -c "$ZIP.sha256" >/dev/null 2>&1) \
    || fail "SHA-256 kontrolü başarısız. Dosya bozuk veya değişmiş. Hiçbir dosya değişmedi. Komutu yeniden çalıştırın."

ditto -x -k "$WORK/$ZIP" "$WORK/unpacked" || fail "Zip dosyası açılamadı: $ZIP."
[ -d "$WORK/unpacked/$APP_NAME.app" ] || fail "Zip dosyasında $APP_NAME.app yok."

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "Çalışan EnvSwitcher kapatılıyor..."
    osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
    i=0
    while pgrep -x "$APP_NAME" >/dev/null 2>&1 && [ "$i" -lt 5 ]; do
        sleep 1
        i=$((i + 1))
    done
    pkill -x "$APP_NAME" 2>/dev/null || true
fi

TARGET="$DEST_DIR/$APP_NAME.app"
SUDO=""
if [ ! -w "$DEST_DIR" ] || { [ -e "$TARGET" ] && [ ! -w "$TARGET" ]; }; then
    echo "$DEST_DIR klasörüne yazma izni yok. Kurulum yönetici şifresi ister."
    SUDO="sudo"
fi
$SUDO rm -rf "$TARGET"
$SUDO ditto "$WORK/unpacked/$APP_NAME.app" "$TARGET"
# curl sets no quarantine flag. A copy from a browser download can still carry one.
$SUDO xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

open "$TARGET"
echo "EnvSwitcher $VERSION kuruldu: $TARGET"
