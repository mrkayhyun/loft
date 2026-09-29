#!/usr/bin/env bash
# Fail when a UI string or engine category lacks a Korean translation, or when
# a translation's format specifiers don't match its key.
# Usage: scripts/check-l10n.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
L10N="$ROOT/app/Localization"
EXTRACT="$(mktemp -d)"
trap 'rm -rf "$EXTRACT"' EXIT

swift build -c release --package-path "$ROOT/app" \
    -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$EXTRACT" >/dev/null

for table in "$L10N"/*.lproj/*.strings; do
    plutil -lint -s "$table" || { echo "invalid strings file: $table" >&2; exit 1; }
done

python3 - "$EXTRACT" "$L10N" "$ROOT/engine/rules/clean.toml" <<'PY'
import glob, json, re, subprocess, sys

extract, l10n, catalog = sys.argv[1:]

def load(path):
    out = subprocess.run(["plutil", "-convert", "json", "-o", "-", path], capture_output=True, check=True)
    return json.loads(out.stdout)

keys = set()
for path in glob.glob(f"{extract}/*.stringsdata"):
    for entries in json.load(open(path)).get("tables", {}).values():
        keys.update(e["key"] for e in entries)

ignored = {line.rstrip("\n") for line in open(f"{l10n}/untranslated.txt") if line.strip() and not line.startswith("#")}
ui = load(f"{l10n}/ko.lproj/Localizable.strings")
engine = load(f"{l10n}/ko.lproj/Engine.strings")
ids = re.findall(r'^id = "([^"]+)"', open(catalog).read(), re.M)

spec = re.compile(r"%(?:\d+\$)?(ll[du]|lf|@|d|f)")
def specs(text):
    return sorted(spec.findall(text))

problems = []
problems += [f"missing ko translation: {k!r}" for k in sorted(keys - ignored - ui.keys())]
problems += [f"stale ko translation (no longer used): {k!r}" for k in sorted(ui.keys() - keys)]
problems += [f"format mismatch: {k!r} → {v!r}" for k, v in ui.items() if k in keys and specs(k) != specs(v)]
for cid in ids:
    for field in ("name", "summary"):
        if f"category.{cid}.{field}" not in engine:
            problems.append(f"missing engine translation: category.{cid}.{field}")

if problems:
    print("\n".join(problems), file=sys.stderr)
    sys.exit(1)
print(f"l10n ok: {len(keys - ignored)} UI strings, {len(ids)} categories translated")
PY
