#!/usr/bin/env bash
# skills-router benchmark — category accuracy over fixtures/test-cases.jsonl.
# Usage: benchmark.sh [cases.jsonl]   Exit 0 when accuracy >= threshold (80%).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CASES="${1:-$SCRIPT_DIR/../fixtures/test-cases.jsonl}"
THRESHOLD="${SKILLS_ROUTER_BENCH_THRESHOLD:-80}"

[ -f "$CASES" ] || { echo "ERROR: no cases file at $CASES" >&2; exit 2; }

total=0
correct=0
misses=""

# One classifier process for the whole run (--batch), paired with expectations
prompts=$(jq -r '.prompt' "$CASES")
expected=$(jq -r '.category' "$CASES")
results=$(printf '%s\n' "$prompts" | "$SCRIPT_DIR/classify.sh" --batch | jq -r '.category')

while IFS=$'\t' read -r want got prompt; do
  [ -n "$want" ] || continue
  total=$((total + 1))
  if [ "$want" = "$got" ]; then
    correct=$((correct + 1))
  else
    misses="${misses}  MISS: want=${want} got=${got} :: ${prompt}\n"
  fi
done < <(paste <(printf '%s\n' "$expected") <(printf '%s\n' "$results") <(printf '%s\n' "$prompts"))

[ "$total" -gt 0 ] || { echo "ERROR: no cases in $CASES" >&2; exit 2; }
pct=$(( correct * 100 / total ))
echo "skills-router benchmark: ${correct}/${total} (${pct}%) — threshold ${THRESHOLD}%"
[ -n "$misses" ] && printf '%b' "$misses"

[ "$pct" -ge "$THRESHOLD" ]
