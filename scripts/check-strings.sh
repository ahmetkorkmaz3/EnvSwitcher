#!/bin/sh
# Checks the translation files (spec 2026-10-08 localization, section 4).
# 1. Each file is a valid .strings file. 2. Both files have the same keys.
# 3. Each translation has the same format specifiers as its key.
# 4. The code uses only keys that the files contain, and the files contain no unused keys.
#    The compiler lists the keys of the code (-emit-localized-strings).
set -eu
cd "$(dirname "$0")/.."

EN="Resources/en.lproj/Localizable.strings"
TR="Resources/tr.lproj/Localizable.strings"

plutil -lint -s "$EN" "$TR"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
plutil -convert json -o "$TMP/en.json" "$EN"
plutil -convert json -o "$TMP/tr.json" "$TR"

mkdir "$TMP/loc"
swift build --target EnvSwitcher -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$TMP/loc" >"$TMP/build.log" 2>&1 \
    || { cat "$TMP/build.log" >&2; exit 1; }

/usr/bin/python3 - "$TMP/en.json" "$TMP/tr.json" "$TMP/loc" <<'PY'
import glob, json, os, re, sys
en = json.load(open(sys.argv[1]))
tr = json.load(open(sys.argv[2]))
used = {}
for path in glob.glob(os.path.join(sys.argv[3], "*.stringsdata")):
    data = json.load(open(path))
    if "/Sources/EnvSwitcher/" not in data["source"]:
        continue
    for entry in data["tables"].get("Localizable", []):
        name = os.path.relpath(data["source"]) + ":" + str(entry["location"]["startingLine"])
        used.setdefault(entry["key"], name)
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
for key in sorted(set(used) - set(en)):
    errors.append(f"key in code but not in the files: {key!r} ({used[key]})")
for key in sorted(set(en) - set(used)):
    errors.append(f"key in the files but not in code: {key!r}")
for line in errors:
    print(line, file=sys.stderr)
sys.exit(1 if errors else 0)
PY
echo "Translations OK ($(grep -c '^"' "$EN") keys)"
