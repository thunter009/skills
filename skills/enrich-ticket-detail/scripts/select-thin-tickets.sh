#!/usr/bin/env bash
# select-thin-tickets.sh — list the OPEN tracker items in this project whose
# description is missing or too thin to triage from. Read-only. Emits NDJSON,
# one object per item: {source, id, title, desc_len, priority, current_description}.
#
# These are the candidates for enrichment. The agent then mines context, drafts a
# cold-start-complete description, verifies it, and applies it via apply-description.sh.
#
#   THRESHOLD   max description length (chars) still considered "thin" (default 80)
#   TD_PROJECT  override the Todoist project (id or name) for this repo
#   TD_SKIP=1   skip Todoist; beads only
#   BD_SKIP=1   skip beads; Todoist only
#   TD_BIN      path to the `td` CLI (default: resolve from PATH, then pnpm global)
set -euo pipefail

THRESHOLD="${THRESHOLD:-80}"
BR_BIN="$(command -v br || true)"
TD_BIN="${TD_BIN:-$(command -v td || echo "$HOME/Library/pnpm/bin/td")}"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
REPO_NAME="$(basename "$REPO_ROOT")"

# --- beads: open issues with a thin/empty description (from cwd .beads/) ---
if [ "${BD_SKIP:-0}" != 1 ] && [ -n "$BR_BIN" ] && [ -d "$REPO_ROOT/.beads" ]; then
  ( cd "$REPO_ROOT" && "$BR_BIN" list --json 2>/dev/null ) \
    | jq -c --argjson t "$THRESHOLD" '
        .issues[]? | select(.status != "closed")
        | {source:"bd", id:.id, title:.title,
           desc_len:((.description // "")|length),
           priority:.priority,
           current_description:(.description // "")}
        | select(.desc_len <= $t)'
fi

# --- todoist: active tasks in the matched project with a thin/empty description ---
if [ "${TD_SKIP:-0}" != 1 ] && { [ -x "$TD_BIN" ] || command -v "$TD_BIN" >/dev/null 2>&1; }; then
  proj_id=""
  if [ -n "${TD_PROJECT:-}" ]; then
    proj_id=$("$TD_BIN" project list --json 2>/dev/null | jq -r --arg q "$TD_PROJECT" '
      [ (.results // .)[]? | select(.id == $q or .name == $q) | .id ] | .[0] // empty')
    [ -z "$proj_id" ] && proj_id="$TD_PROJECT"
  else
    # Match repo dir to a Todoist project by normalized name (strip Johnny-Decimal
    # prefix, unify -/_ and case): e.g. agent-skills <-> 21.04_agent_skills.
    proj_id=$("$TD_BIN" project list --json 2>/dev/null | jq -r --arg repo "$REPO_NAME" '
      ($repo | ascii_downcase | gsub("[-_]"; " ")) as $rn
      | [ (.results // .)[]?
          | (.name | gsub("^[0-9]+([.][0-9]+)?_"; "") | gsub("[-_]"; " ") | ascii_downcase
             | gsub("^ +| +$"; "")) as $pn
          | select($pn == $rn) | .id ] | .[0] // empty')
  fi
  if [ -n "$proj_id" ]; then
    "$TD_BIN" task list --project "$proj_id" --json --full 2>/dev/null \
      | jq -c --argjson t "$THRESHOLD" '
          .results[]?
          | {source:"td", id:.id, title:.content,
             desc_len:((.description // "")|length),
             priority:.priority,
             current_description:(.description // "")}
          | select(.desc_len <= $t)'
  else
    echo "select-thin-tickets: no Todoist project matches repo '$REPO_NAME' (set TD_PROJECT) — beads only." >&2
  fi
fi
