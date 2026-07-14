#!/usr/bin/env bash
# assemble.sh — final graph assembly. Combine assembled-graph.json (post-merge) with
# layers.json + tour.json + project metadata into .understand-anything/knowledge-graph.json,
# dropping dangling layer/tour refs and validating referential integrity.
# Usage: assemble.sh <PROJECT_ROOT>
set -euo pipefail

PROJECT_ROOT="${1:?usage: assemble.sh <PROJECT_ROOT>}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd -P)"
UA="$PROJECT_ROOT/.understand-anything"
INT="$UA/intermediate"
COMMIT="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

for f in assembled-graph.json scan-result.json layers.json tour.json; do
  [ -f "$INT/$f" ] || { echo "assemble: missing $INT/$f" >&2; exit 2; }
done

COMMIT="$COMMIT" TS="$TS" python3 - "$INT" "$UA" <<'PY'
import json, os, sys
INT, UA = sys.argv[1], sys.argv[2]
commit, ts = os.environ["COMMIT"], os.environ["TS"]
g = json.load(open(f"{INT}/assembled-graph.json"))
scan = json.load(open(f"{INT}/scan-result.json"))
layers = json.load(open(f"{INT}/layers.json"))
if isinstance(layers, dict): layers = layers.get("layers", layers)
tour = json.load(open(f"{INT}/tour.json"))
if isinstance(tour, dict): tour = tour.get("tour", tour.get("steps", tour))

ids = {n["id"] for n in g["nodes"]}
for lay in layers:
    nl = lay.get("nodeIds") or lay.get("nodes") or []
    lay["nodeIds"] = [x for x in nl if x in ids]
    lay.pop("nodes", None)
for s in tour:
    s["nodeIds"] = [x for x in (s.get("nodeIds") or []) if x in ids]
tour = sorted(tour, key=lambda s: s.get("order", 0))

graph = {
    "version": "1.0.0",
    "project": {
        "name": scan["name"], "languages": scan["languages"],
        "frameworks": scan["frameworks"], "description": scan["description"],
        "analyzedAt": ts, "gitCommitHash": commit,
    },
    "nodes": g["nodes"], "edges": g["edges"], "layers": layers, "tour": tour,
}
dangling = [e for e in g["edges"] if e["source"] not in ids or e["target"] not in ids]
if dangling:
    sample = ", ".join(f"{e.get('source')}->{e.get('target')}" for e in dangling[:5])
    print(f"assemble: ERROR {len(dangling)} dangling edges remain: {sample}", file=sys.stderr)
    sys.exit(1)
json.dump(graph, open(f"{UA}/knowledge-graph.json", "w"), indent=2)
json.dump({"gitCommitHash": commit, "analyzedAt": ts, "version": "1.0.0"},
          open(f"{UA}/meta.json", "w"), indent=2)
kb = round(os.path.getsize(f"{UA}/knowledge-graph.json") / 1024)
print(f"assemble: nodes={len(graph['nodes'])} edges={len(graph['edges'])} "
      f"layers={len(layers)} tour={len(tour)} dangling_edges=0 size={kb}KB")
PY

echo "assemble: wrote $UA/knowledge-graph.json"
