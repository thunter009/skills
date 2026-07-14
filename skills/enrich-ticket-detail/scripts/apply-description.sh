#!/usr/bin/env bash
# apply-description.sh — gated write-back of an enriched description to one tracker
# item. Shows a unified diff (current -> new) and, by default, applies NOTHING:
# it is dry-run unless you pass --yes (or set APPLY=1). This is the approval gate.
#
# Usage:
#   apply-description.sh <bd|td> <id> <descfile>     # preview diff (no write)
#   apply-description.sh <bd|td> <id> <descfile> --yes   # apply after you've reviewed
#   ... | apply-description.sh <bd|td> <id> -        # read new description from stdin
#
# Idempotent: if the new description equals the current one, it reports "unchanged"
# and writes nothing. Re-runnable.
#
# After a beads write you must flush + commit:  br sync --flush-only && git add .beads
set -euo pipefail

APPLY="${APPLY:-0}"
args=()
for a in "$@"; do
  case "$a" in
    --yes|-y) APPLY=1 ;;
    *) args+=("$a") ;;
  esac
done
set -- ${args[@]+"${args[@]}"}   # bash-3.2-safe expansion of a possibly-empty array

SRC="${1:-}"; ID="${2:-}"; DESCFILE="${3:-}"
if [ -z "$SRC" ] || [ -z "$ID" ] || [ -z "$DESCFILE" ]; then
  echo "usage: apply-description.sh <bd|td> <id> <descfile|-> [--yes]" >&2; exit 2
fi

TD_BIN="${TD_BIN:-$(command -v td || echo "$HOME/Library/pnpm/bin/td")}"
BR_BIN="$(command -v br || true)"

# --- read the new description (file or stdin) ---
new_tmp="$(mktemp)"; cur_tmp=""; trap 'rm -f "$new_tmp" "$cur_tmp"' EXIT
if [ "$DESCFILE" = "-" ]; then cat > "$new_tmp"; else cat "$DESCFILE" > "$new_tmp"; fi

# --- read the current description from the tracker ---
cur_tmp="$(mktemp)"
case "$SRC" in
  bd)
    [ -n "$BR_BIN" ] || { echo "br not found" >&2; exit 1; }
    "$BR_BIN" show "$ID" --json 2>/dev/null \
      | jq -r 'if type=="array" then .[0].description else .description end // ""' > "$cur_tmp" ;;
  td)
    "$TD_BIN" task view "$ID" --json 2>/dev/null | jq -r '.description // ""' > "$cur_tmp" ;;
  *) echo "unknown source '$SRC' (want bd|td)" >&2; exit 2 ;;
esac

# --- idempotency: skip if identical ---
if diff -q "$cur_tmp" "$new_tmp" >/dev/null 2>&1; then
  echo "apply-description: $SRC $ID — unchanged, nothing to do."
  exit 0
fi

# --- show the diff ---
echo "===== $SRC $ID : description diff (current -> new) ====="
diff -u --label "current" "$cur_tmp" --label "new" "$new_tmp" || true
echo "======================================================="

if [ "$APPLY" != 1 ]; then
  echo "apply-description: DRY-RUN (no write). Re-run with --yes to apply."
  exit 0
fi

# --- apply ---
case "$SRC" in
  bd)
    "$BR_BIN" update "$ID" --description="$(cat "$new_tmp")"
    echo "apply-description: wrote beads $ID. Remember: br sync --flush-only && git add .beads && commit." ;;
  td)
    # --stdin keeps long/multiline descriptions safe.
    "$TD_BIN" task update "$ID" --stdin < "$new_tmp" >/dev/null
    echo "apply-description: wrote todoist $ID." ;;
esac
