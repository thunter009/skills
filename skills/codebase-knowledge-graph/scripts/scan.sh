#!/usr/bin/env bash
# scan.sh — deterministic scan + batch for a target codebase using UA's bundled scripts.
# Usage: scan.sh <PROJECT_ROOT> <name> <description> [frameworks_csv]
# Requires PLUGIN_ROOT/SKILL_DIR in env (source ua-env.sh first).
set -euo pipefail

PROJECT_ROOT="${1:?usage: scan.sh <PROJECT_ROOT> <name> <description> [frameworks_csv]}"
NAME="${2:?missing project name}"
DESCRIPTION="${3:?missing project description}"
FRAMEWORKS_CSV="${4:-}"

: "${SKILL_DIR:?source ua-env.sh first (SKILL_DIR unset)}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd -P)"
INT="$PROJECT_ROOT/.understand-anything/intermediate"
TMP="$PROJECT_ROOT/.understand-anything/tmp"
mkdir -p "$INT" "$TMP"

# 1. starter ignore file (delegates to core)
PLUGIN_ROOT="${PLUGIN_ROOT:-}" node "$SKILL_DIR/generate-ignore.mjs" "$PROJECT_ROOT" >&2 || true

# 2. file enumeration + language + category + line counts (tree-sitter)
node "$SKILL_DIR/scan-project.mjs" "$PROJECT_ROOT" "$TMP/ua-scan-files.json" >&2

# 3. import resolution
python3 - "$TMP/ua-scan-files.json" "$PROJECT_ROOT" "$TMP/ua-import-map-input.json" <<'PY'
import json, sys
scan = json.load(open(sys.argv[1]))
files = [{"path": f["path"], "language": f["language"], "fileCategory": f["fileCategory"]} for f in scan["files"]]
json.dump({"projectRoot": sys.argv[2], "files": files}, open(sys.argv[3], "w"))
PY
node "$SKILL_DIR/extract-import-map.mjs" "$TMP/ua-import-map-input.json" "$TMP/ua-import-map-output.json" >&2

# 4. assemble scan-result.json (the deterministic outputs + caller-supplied metadata)
python3 - "$TMP/ua-scan-files.json" "$TMP/ua-import-map-output.json" "$INT/scan-result.json" \
  "$NAME" "$DESCRIPTION" "$FRAMEWORKS_CSV" <<'PY'
import json, sys
scan = json.load(open(sys.argv[1]))
imp = json.load(open(sys.argv[2]))
out_path, name, description, fw_csv = sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
frameworks = [s.strip() for s in fw_csv.split(",") if s.strip()]
desc = description
if scan["totalFiles"] > 100:
    desc += " Note: over 100 source files; consider scoping analysis to a subdirectory for faster results."
out = {
    "name": name,
    "description": desc,
    "languages": sorted(scan["stats"]["byLanguage"].keys()),
    "frameworks": frameworks,
    "files": scan["files"],
    "totalFiles": scan["totalFiles"],
    "filteredByIgnore": scan["filteredByIgnore"],
    "estimatedComplexity": scan["estimatedComplexity"],
    "importMap": imp["importMap"],
}
json.dump(out, open(out_path, "w"), indent=2)
print(f"scan-result: files={out['totalFiles']} complexity={out['estimatedComplexity']} "
      f"languages={','.join(out['languages'])}", file=sys.stderr)
PY

# 5. semantic batching
node "$SKILL_DIR/compute-batches.mjs" "$PROJECT_ROOT" >&2

# 6. print the batch plan to stdout for the orchestrator
python3 - "$INT/batches.json" <<'PY'
import json, sys
b = json.load(open(sys.argv[1]))["batches"]
print(f"TOTAL_BATCHES={len(b)}")
for x in b:
    files = x.get("files", [])
    print(f"  batch {x['batchIndex']}: {len(files)} files")
PY
