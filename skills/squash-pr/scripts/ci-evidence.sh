#!/usr/bin/env bash
# ci-evidence.sh — did CI actually RUN for this PR's current head?
#
# The merge gate's green leg asks "did anything fail?". That is the wrong question when the
# answer is "nothing ran": a PR with zero workflow runs has no failing checks, so a gate that
# only looks for failures reads it as green and merges code that nothing tested.
#
# A private repo's PR #1608 merged on 2026-08-11 in exactly that state — one green CodeRabbit app check and
# zero GitHub Actions runs. Actions was healthy repo-wide (sibling PRs carried 14-15 checks);
# the runs were simply never created for that SHA, and a rebase did not bring them back. It
# reached main and shipped in a release having been tested by nothing.
#
# POSITIVE EVIDENCE, same principle as review-evidence.sh: prove runs happened rather than
# fail to find a complaint. "No failures" and "no runs" are indistinguishable downstream,
# which is exactly why the absence must be checked for directly.
#
# ── design notes, each one load-bearing ──────────────────────────────────────────────────
#
# SAME SOURCE AS LEG 3, AT THE HEAD SHA. This reads `actions/runs?head_sha=<head>`, the API
# ci-verdict.sh (the green leg) reads its jobs from. It used to read `statusCheckRollup`, but a
# fine-grained PAT cannot hold Checks permission, so the rollup failed on every PR there
# (dev-box, 2026-10-26..29: the squash loop skipped every PR). Legs that read different APIs
# describe different moments: a queued run visible to one and absent from the other let both
# pass on a PR that had not been validated. One API at one head cannot disagree with itself.
#
# COMPLETED ONLY. An in-flight run is not evidence that CI ran, it is evidence that CI is
# running. Refusing costs one tick — the loop re-evaluates on its next cycle and the PR lands
# then — whereas accepting reopens the race above.
#
# DISTINCT WORKFLOW RUNS, not check entries. One workflow re-run three times is one workflow's
# worth of evidence, and `--min` must not be satisfiable by retries of a single job.
#
# ACTIONS ONLY, identified by a `/actions/runs/<id>/` details URL. Third-party app checks
# (CodeRabbit, coverage bots) are excluded on purpose: they are the signal that made #1608
# look green. LIMITATION, stated rather than hidden — a repo whose CI is entirely non-Actions
# (CircleCI, Buildkite) will always report CI_ABSENT here, so this leg must not be enabled
# there. It is a gate for Actions-based repos.
#
# WHAT IT DOES NOT SEE: a workflow that ran but whose jobs all skipped internally reports
# `success` at run level. Detecting that needs a jobs API call per run; out of scope, and the
# `skipped` conclusion filter already catches the common path-filter case.
#
# EXIT CODES — 3 is not a pass:
#   0  CI_RAN         at least --min distinct completed Actions workflow run(s) at this head
#   1  CI_ABSENT      fewer than that. A definite answer: refuse the merge.
#   2  usage error
#   3  INDETERMINATE  could not tell — no gh/jq, API error, malformed payload. The caller MUST
#                     treat this like 1. A machine that cannot answer is exactly when a merge
#                     gate is most likely to be wrong.
#
# Usage:
#   ci-evidence.sh <pr-number> [--repo owner/name] [--min N] [--json]
#   CI_EVIDENCE_FIXTURE_DIR=<dir> ci-evidence.sh <pr-number>   # offline; see tests/
#
# Fixture dir contents:
#   rollup.json   rows {status, conclusion, detailsUrl, name} — the live path builds one row
#                 per workflow run at the head (html_url as detailsUrl, workflow name as name)
set -uo pipefail

MIN=1
PR=""; REPO=""; JSON=0

need_value() { # flag  remaining-count
  [ "$2" -ge 2 ] || { echo "$1 requires a value" >&2; exit 2; }
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)    need_value --repo $#; REPO="$2"; shift 2 ;;
    --min)     need_value --min  $#; MIN="$2";  shift 2 ;;
    --json)    JSON=1; shift ;;
    -h|--help) sed -n '2,56p' "$0"; exit 0 ;;
    -*)        echo "unknown flag: $1" >&2; exit 2 ;;
    *)         PR="$1"; shift ;;
  esac
done
[ -n "$PR" ] || { echo "usage: ci-evidence.sh <pr-number> [--repo owner/name] [--min N]" >&2; exit 2; }
# --min 0 would make `runs >= min` vacuously true and silently disable the whole guard.
case "$MIN" in ''|*[!0-9]*) echo "--min must be a positive integer" >&2; exit 2 ;; esac
[ "$MIN" -ge 1 ] || { echo "--min must be >= 1 (0 would disable the guard)" >&2; exit 2; }

FIX="${CI_EVIDENCE_FIXTURE_DIR:-}"

emit() { # verdict reason   — built with jq so a workflow name containing quotes cannot
         #                    produce invalid JSON on the documented --json path.
  if [ "$JSON" = 1 ]; then
    jq -nc --arg v "$1" --arg r "$2" --arg p "$PR" '{verdict:$v, reason:$r, pr:$p}'
  else
    printf '%s: %s\n' "$1" "$2"
  fi
}

if [ -n "$FIX" ]; then
  command -v jq >/dev/null 2>&1 || { echo "INDETERMINATE: jq not on PATH" >&2; exit 3; }
  [ -d "$FIX" ] || { emit INDETERMINATE "fixture dir not found: $FIX"; exit 3; }
  if [ -s "$FIX/rollup.json" ]; then ROLLUP="$(cat "$FIX/rollup.json")"; else ROLLUP='[]'; fi
else
  command -v gh >/dev/null 2>&1 || { echo "INDETERMINATE: gh not on PATH" >&2; exit 3; }
  command -v jq >/dev/null 2>&1 || { echo "INDETERMINATE: jq not on PATH" >&2; exit 3; }
  R=(); [ -n "$REPO" ] && R=(--repo "$REPO")
  GH_ERR="$(mktemp "${TMPDIR:-/tmp}/ci-evidence-err.XXXXXX")"
  trap 'rm -f "$GH_ERR"' EXIT
  if [ -z "$REPO" ]; then
    REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" || {
      emit INDETERMINATE "cannot resolve repo; pass --repo"; exit 3; }
  fi
  HEAD="$(gh pr view "$PR" "${R[@]}" --json headRefOid -q .headRefOid 2>"$GH_ERR")"
  [[ "$HEAD" =~ ^[0-9a-f]{40}$ ]] || { emit INDETERMINATE "cannot read the head of #$PR"; exit 3; }
  # One row per workflow run at the head, in the rows shape the counting below reads.
  ROLLUP="$(gh api --paginate --slurp "repos/$REPO/actions/runs?head_sha=$HEAD&per_page=100" 2>"$GH_ERR" \
    | jq -c '[ .[].workflow_runs[]
               | { name, status: (.status // "" | ascii_upcase),
                   conclusion: (.conclusion // "" | ascii_upcase), detailsUrl: .html_url } ]')" || {
    # Name a permission gap: a token without Actions: Read cannot list runs.
    if grep -q 'Resource not accessible by' "$GH_ERR"; then
      emit INDETERMINATE "token lacks Actions:read — cannot list workflow runs at ${HEAD:0:12} for #$PR (atrium-loops scripts/check-gh-token.sh)"
    else
      emit INDETERMINATE "cannot read workflow runs at ${HEAD:0:12} for #$PR"
    fi
    exit 3; }
  rm -f "$GH_ERR"
fi

echo "$ROLLUP" | jq -e 'type=="array"' >/dev/null 2>&1 || {
  emit INDETERMINATE "workflow run list is not an array"; exit 3; }

# Distinct Actions workflow-run ids whose check COMPLETED with a conclusion that means the
# work actually happened. SKIPPED/CANCELLED validated nothing; anything else (SUCCESS,
# FAILURE, TIMED_OUT, ...) means it ran — whether it PASSED is leg 3's question, not this one.
RUN_IDS="$(echo "$ROLLUP" | jq -r '
  [ .[]
    | select((.status // "") == "COMPLETED")
    | select(((.conclusion // "") | ascii_upcase) as $c | $c != "SKIPPED" and $c != "CANCELLED")
    | (.detailsUrl // .targetUrl // "")
    | (capture("/actions/runs/(?<id>[0-9]+)")? | .id)
  ] | map(select(. != null)) | unique')"

COUNT="$(echo "$RUN_IDS" | jq 'length')"
TOTAL="$(echo "$ROLLUP" | jq 'length')"
NAMES="$(echo "$ROLLUP" | jq -r '
  [ .[] | select((.status // "") == "COMPLETED")
        | select(((.conclusion // "") | ascii_upcase) as $c | $c != "SKIPPED" and $c != "CANCELLED")
        | select(((.detailsUrl // .targetUrl // "") | test("/actions/runs/")))
        | (.name // "?") ] | unique | join(", ")')"

if [ "$COUNT" -ge "$MIN" ] 2>/dev/null; then
  emit CI_RAN "$COUNT distinct completed Actions workflow run(s): $NAMES"
  exit 0
fi

if [ "$TOTAL" -eq 0 ] 2>/dev/null; then
  emit CI_ABSENT "no checks at all on #$PR — nothing tested this code; a green rollup here means only that nothing ran"
  exit 1
fi

emit CI_ABSENT "$TOTAL check entr(ies) on #$PR but only $COUNT distinct completed Actions workflow run(s), fewer than the required $MIN — third-party app checks and in-flight or skipped runs are not evidence that CI ran"
exit 1
