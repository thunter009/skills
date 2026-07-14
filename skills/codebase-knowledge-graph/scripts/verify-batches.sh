#!/usr/bin/env bash
# verify-batches.sh — the integrity guard. Assert every batchIndex in batches.json
# has a corresponding intermediate/batch-<i>.json (or batch-<i>-part-*.json) on disk.
# Catches the `rm batch-1*` glob-collision that silently deletes batch-10/11/12.
# Usage: verify-batches.sh <PROJECT_ROOT>
# Exit 0 = complete. Exit 1 = prints "MISSING=<i> <j> ..." for re-dispatch.
set -euo pipefail

PROJECT_ROOT="${1:?usage: verify-batches.sh <PROJECT_ROOT>}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd -P)"
INT="$PROJECT_ROOT/.understand-anything/intermediate"
BATCHES="$INT/batches.json"
[ -f "$BATCHES" ] || { echo "verify-batches: $BATCHES not found (run scan.sh first)" >&2; exit 2; }

python3 - "$BATCHES" "$INT" <<'PY'
import json, os, re, sys
batches_path, int_dir = sys.argv[1], sys.argv[2]
indexes = [b["batchIndex"] for b in json.load(open(batches_path))["batches"]]
present = set()
invalid = []
pat = re.compile(r"^batch-(\d+)(?:-part-\d+)?\.json$")
for fn in os.listdir(int_dir):
    m = pat.match(fn)
    if m:
        path = os.path.join(int_dir, fn)
        try:
            with open(path, encoding="utf-8") as handle:
                payload = json.load(handle)
            if not payload:
                raise ValueError("empty JSON payload")
        except (json.JSONDecodeError, OSError, ValueError) as exc:
            invalid.append(f"{fn}:{type(exc).__name__}")
            continue
        present.add(int(m.group(1)))
missing = sorted(i for i in indexes if i not in present)
if invalid:
    print("INVALID=" + " ".join(invalid))
if missing:
    print("MISSING=" + " ".join(str(i) for i in missing))
    print(f"verify-batches: {len(missing)}/{len(indexes)} batches missing or invalid output — re-dispatch them.", file=sys.stderr)
    sys.exit(1)
if invalid:
    print(f"verify-batches: {len(invalid)} invalid batch output file(s) found — remove or re-dispatch them.", file=sys.stderr)
    sys.exit(1)
print(f"verify-batches: OK — all {len(indexes)} batchIndexes have output.", file=sys.stderr)
PY
