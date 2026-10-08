#!/bin/sh
# Prints the CHANGELOG.md section of one version. Fails when the section is missing or empty.
# Usage: scripts/changelog-section.sh 0.2.0 [CHANGELOG.md]
set -eu
VERSION="$1"
FILE="${2:-CHANGELOG.md}"

SECTION="$(awk -v v="$VERSION" '
    index($0, "## [" v "]") == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found { print }
' "$FILE")"

if [ -z "$(printf '%s' "$SECTION" | tr -d '[:space:]')" ]; then
    echo "Hata: $FILE içinde \"## [$VERSION]\" bölümü yok veya boş." >&2
    exit 1
fi
printf '%s\n' "$SECTION"
