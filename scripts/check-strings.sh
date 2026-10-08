#!/bin/sh
# Checks the translation files (spec 2026-10-08 localization, section 4).
# 1. Each file is a valid .strings file. 2. Both files have the same keys.
# 3. Each translation has the same format specifiers as its key.
set -eu
cd "$(dirname "$0")/.."

EN="Resources/en.lproj/Localizable.strings"
TR="Resources/tr.lproj/Localizable.strings"

plutil -lint -s "$EN" "$TR"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
plutil -convert json -o "$TMP/en.json" "$EN"
plutil -convert json -o "$TMP/tr.json" "$TR"

/usr/bin/python3 - "$TMP/en.json" "$TMP/tr.json" <<'PY'
import json, re, sys
en = json.load(open(sys.argv[1]))
tr = json.load(open(sys.argv[2]))
spec = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f)")
def specs(text):
    return sorted(re.sub(r"\d+\$", "", s) for s in spec.findall(text))
errors = []
for key in sorted(set(en) ^ set(tr)):
    errors.append(f"key only in {'en' if key in en else 'tr'}: {key!r}")
for key in sorted(set(en) & set(tr)):
    for lang, text in (("en", en[key]), ("tr", tr[key])):
        if specs(text) != specs(key):
            errors.append(f"format specifiers differ ({lang}): {key!r}")
for line in errors:
    print(line, file=sys.stderr)
sys.exit(1 if errors else 0)
PY
echo "Translations OK ($(grep -c '^"' "$EN") keys)"
