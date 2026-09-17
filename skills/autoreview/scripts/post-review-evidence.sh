#!/usr/bin/env bash
# post-review-evidence.sh — leave the autoreview verdict ON THE PR before a self-merge.
#
# WHY. A local `autoreview` run satisfies the merge-authority rule (CI green + review clean),
# but it leaves no artifact on GitHub. The squash drain's gate (`squash-pr/scripts/
# review-evidence.sh`) and any later audit then read the PR as UNREVIEWED — which is exactly
# what happened on agent-skills #414 (2026-09-17: codex-reviewed locally, three findings fixed,
# self-merged, zero review bodies on the PR). This script turns the final helper run into a
# COMMENT review pinned to the current head SHA, in the shape review-evidence.sh accepts:
# >= 200 chars, a `### Files` section, per-finding `path:line` citations, and
# "No findings after checking:" on a clean run.
#
# NEVER posts APPROVE or REQUEST_CHANGES — the event is always COMMENT. An agent reviewing its
# own PR is evidence, not approval authority.
#
# Usage:
#   post-review-evidence.sh <pr> --from <autoreview --json-output file> [--repo o/r]
#                           [--engine codex] [--rounds N] [--dry-run]
#   # offline (tests): --dry-run --head <sha> --files a.py,b.py   (no gh calls at all)
#
# Exit: 0 posted (or dry-run printed) · 1 refused (head moved / no files / bad json) · 2 usage
# shellcheck disable=SC2016  # backticks in printf formats are markdown, not command substitution
set -uo pipefail
PR=""; FROM=""; REPO=""; ENGINE="codex"; ROUNDS=""; DRY=0; HEAD=""; FILES_CSV=""
need() { [ $# -ge 2 ] || { echo "flag $1 needs a value" >&2; exit 2; }; }  # a trailing flag must not loop forever
while [ $# -gt 0 ]; do
  case "$1" in
    --from)    need "$@"; FROM="$2"; shift 2 ;;
    --repo)    need "$@"; REPO="$2"; shift 2 ;;
    --engine)  need "$@"; ENGINE="$2"; shift 2 ;;
    --rounds)  need "$@"; ROUNDS="$2"; shift 2 ;;
    --head)    need "$@"; HEAD="$2"; shift 2 ;;
    --files)   need "$@"; FILES_CSV="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    -*)        echo "unknown flag: $1" >&2; exit 2 ;;
    *)         PR="$1"; shift ;;
  esac
done
[ -n "$PR" ] && [ -n "$FROM" ] || { echo "usage: post-review-evidence.sh <pr> --from <json> [--repo o/r]" >&2; exit 2; }
[ -f "$FROM" ] || { echo "refused: $FROM not found" >&2; exit 1; }
jq -e 'type=="object" and (.findings|type=="array")' "$FROM" >/dev/null 2>&1 \
  || { echo "refused: $FROM is not an autoreview --json-output document" >&2; exit 1; }

REPO_ARGS=(); [ -n "$REPO" ] && REPO_ARGS=(--repo "$REPO")

# --- head + changed files: from flags (offline) or from gh ---------------------------------
if [ -z "$HEAD" ] || [ -z "$FILES_CSV" ]; then
  command -v gh >/dev/null 2>&1 || { echo "refused: gh not available and --head/--files not given" >&2; exit 1; }
  META="$(gh pr view "$PR" "${REPO_ARGS[@]}" --json headRefOid,files 2>/dev/null)" \
    || { echo "refused: gh pr view $PR failed" >&2; exit 1; }
  [ -n "$HEAD" ]      || HEAD="$(jq -r '.headRefOid // ""' <<<"$META")"
  [ -n "$FILES_CSV" ] || FILES_CSV="$(jq -r '[.files[].path] | join(",")' <<<"$META")"
fi
[ -n "$HEAD" ] || { echo "refused: no head SHA" >&2; exit 1; }
[ -n "$FILES_CSV" ] || { echo "refused: PR has no changed files" >&2; exit 1; }

# --- compose ------------------------------------------------------------------------------
N_FIND="$(jq '.findings | length' "$FROM")"
OVERALL="$(jq -r '.overall_correctness // "unknown"' "$FROM")"
EXPL="$(jq -r '.overall_explanation // ""' "$FROM")"
CONF="$(jq -r '.overall_confidence // empty' "$FROM")"
case "$OVERALL" in
  *incorrect*|*"not correct"*) VERDICT="CHANGES REQUESTED (findings open)" ;;
  *correct*)                   VERDICT="APPROVE" ;;
  *)                           VERDICT="UNDETERMINED" ;;
esac
[ "$N_FIND" -gt 0 ] && VERDICT="CHANGES REQUESTED (findings open)"

IFS=',' read -r -a FILES <<<"$FILES_CSV"
N_FILES="${#FILES[@]}"
ROUND_NOTE=""; [ -n "$ROUNDS" ] && ROUND_NOTE=", round $ROUNDS"

BODY_FILE="$(mktemp "${TMPDIR:-/tmp}/post-review-evidence.XXXXXX")" || { echo "refused: mktemp failed" >&2; exit 1; }
trap 'rm -f "$BODY_FILE"' EXIT
{
  printf '## Review — %s file(s) read of %s changed\n\n' "$N_FILES" "$N_FILES"
  printf '**Head reviewed:** `%s`\n\n' "${HEAD:0:8}"
  printf '**Engine:** %s via `autoreview` (structured review helper%s), posted by the PR author before self-merge. This is review *evidence*, not approval authority: event is COMMENT.\n\n' "$ENGINE" "$ROUND_NOTE"
  printf '**Verdict: %s**\n\n' "$VERDICT"
  printf '### Files\n'
  for f in "${FILES[@]}"; do printf -- '- `%s`\n' "$f"; done
  printf '\n'
  if [ "$N_FIND" -gt 0 ]; then
    printf '**Findings (%s, open at this head)**\n' "$N_FIND"
    jq -r '.findings[] | "- [\(.priority // "P?")] `\(.code_location.file_path // "?"):\(.code_location.line // 0)` — \(.title // "untitled")"' "$FROM"
    printf '\n'
  else
    printf '**HIGH**\n- None.\n\n'
    printf '**No findings after checking:** '
    for i in "${!FILES[@]}"; do [ "$i" -gt 0 ] && printf ', '; printf '%s' "${FILES[$i]}"; done
    printf '\n\n'
  fi
  [ -n "$EXPL" ] && printf '**Overall:** %s' "$EXPL"
  [ -n "$CONF" ] && printf ' (confidence %s)' "$CONF"
  printf '\n\n**Not reviewed:** none\n'
} > "$BODY_FILE"

LEN="$(wc -c < "$BODY_FILE" | tr -d ' ')"
[ "$LEN" -ge 200 ] || { echo "refused: composed body is $LEN chars (< 200) — would not count as evidence" >&2; exit 1; }

if [ "$DRY" -eq 1 ]; then cat "$BODY_FILE"; exit 0; fi

# --- post, pinned to the head we reviewed ---------------------------------------------------
# Re-read the head right before posting: a review of a moved head is stale by construction.
LIVE_HEAD="$(gh pr view "$PR" "${REPO_ARGS[@]}" --json headRefOid -q .headRefOid 2>/dev/null)"
[ "$LIVE_HEAD" = "$HEAD" ] || { echo "refused: head moved ($HEAD -> $LIVE_HEAD); re-run autoreview on the new head" >&2; exit 1; }

OWNER_REPO="$REPO"
[ -n "$OWNER_REPO" ] || OWNER_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
gh api "repos/$OWNER_REPO/pulls/$PR/reviews" -f event=COMMENT -f commit_id="$HEAD" -F body=@"$BODY_FILE" --jq '"posted review \(.id) at \(.commit_id[0:8]) (\(.state))"'
