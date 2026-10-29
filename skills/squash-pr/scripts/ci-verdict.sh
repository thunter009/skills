#!/usr/bin/env bash
# ci-verdict.sh — is every REQUIRED context green at this PR's exact head?
#
# Every hand-rolled CI-wait loop ended up testing some form of "nothing is pending" over
# `gh pr checks`. That is vacuous when GitHub created no runs: the list then holds only
# non-Actions rows (a rate-limited CodeRabbit line), nothing is pending, and the loop reports
# green. A private repo hit it four times (2026-08-03 #1366, 08-06 #1473 — stale branch;
# 08-26 #2284 — Actions outage; 09-16 #2912 — required aggregator not yet created), twice as a
# false "CI green" told to the operator.
#
# SECOND SOURCE FOR THE EXPECTED SET. A watcher that derives its exit condition from the same
# response it polls cannot tell "not created" from "not required". This script takes the
# required contexts from the base branch's RULESET (`rules/branches/<base>`), then looks each
# one up at the head SHA. A required context with no run is never green.
#
# ACTIONS JOBS, NOT CHECK RUNS. A fine-grained PAT cannot hold Checks permission (only GitHub
# Apps can), so check-runs and statusCheckRollup fail on such a host (dev-box, 2026-10-29). The
# live path lists the Actions runs at the head and their latest-attempt jobs. Each job is a
# check run of the GitHub Actions app (15368) with the same name, id, status and conclusion,
# so the matching below is unchanged. Check runs of other apps are invisible; see INDETERMINATE.
#
# PINNED TO ONE HEAD. Jobs and statuses are read for the head SHA resolved at the start,
# never through the PR's rollup (which can describe a superseded head). The head is re-read at
# the end; if it moved, the answer describes old code and is INDETERMINATE.
#
# PRECEDENCE — first match wins:
#   FAILED      a required context concluded failure/cancelled/timed_out/action_required/...
#   PENDING     a required context is running, OR a required context is missing while any
#               other run at this head is still running. A job whose `needs:` dependency is
#               unfinished is never instantiated, so "missing" is not final until the head
#               is quiet.
#   INDETERMINATE (exit 3) a required context the token cannot observe: pinned to a non-Actions
#               app ("unobservable"), or unpinned with no Actions job and no commit status
#               ("unmapped" — it could be a non-Actions check run, which needs Checks
#               permission to read). Never folded into GREEN.
#   UNTRIGGERED required context(s) have no run and nothing at this head is running. Its own
#               verdict, never folded into PENDING or GREEN: the remedy depends on the cause —
#               stale branch → rebase onto the base; Actions outage → wait (githubstatus.com);
#               never `gh pr merge --admin`.
#   GREEN       every required context present and success/neutral/skipped at the head.
#
# LATEST RUN PER CONTEXT. A re-run leaves the old run in the API. The highest check-run id per
# name wins, so a red run that was re-run green is not FAILED. Check runs match on name and,
# when the ruleset pins one, on `integration_id` == the run's app id. Commit statuses carry no
# app id, so they count only for a context the ruleset does not pin, and only when no check
# run matches.
#
# NO REQUIRED CONTEXTS = INDETERMINATE, not GREEN. An empty required set makes "all required
# passed" vacuous — the same hole this script closes. Use ci-evidence.sh on such a base.
# CLASSIC PROTECTION TOO. `/rules/branches/` returns [] under classic protection, so the
# required set also takes `.protection.required_status_checks.checks` of `branches/<base>`
# (read access suffices). app_id -1/null there means any app.
#
# EXIT CODES — only 0 is a pass:
#   0  GREEN
#   1  FAILED <context>... | PENDING ... | UNTRIGGERED <n> required contexts have no run
#   2  usage error
#   3  INDETERMINATE  could not tell — no gh/jq, API error, malformed payload, no required
#                     contexts, head moved. Callers MUST treat this like 1.
#
# Usage:
#   ci-verdict.sh <pr-number> [--repo owner/name] [--json]
#   CI_VERDICT_FIXTURE_DIR=<dir> ci-verdict.sh <pr-number>   # offline; see tests/
#
# Fixture dir contents:
#   pr.json          {"headRefOid":..., "baseRefName":...} from `gh pr view --json`
#   rules.json       `gh api repos/O/R/rules/branches/<base>` output
#   branch.json      `gh api repos/O/R/branches/<base>` output; optional, defaults to {}
#   check-runs.json  array of check-run-shaped rows {id, name, status, conclusion, app.id}; the
#                    live path builds them from Actions jobs at the head (app.id 15368)
#   statuses.json    array of statuses (`.statuses[]` of commits/<sha>/status); optional
#   pr-after.json    the end-of-run head re-read; optional, defaults to pr.json
set -uo pipefail

PR=""; REPO=""; JSON=0

need_value() { # flag  remaining-count
  [ "$2" -ge 2 ] || { echo "$1 requires a value" >&2; exit 2; }
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)    need_value --repo $#; REPO="$2"; shift 2 ;;
    --json)    JSON=1; shift ;;
    -h|--help) sed -n '2,61p' "$0"; exit 0 ;;
    -*)        echo "unknown flag: $1" >&2; exit 2 ;;
    *)         PR="$1"; shift ;;
  esac
done
[ -n "$PR" ] || { echo "usage: ci-verdict.sh <pr-number> [--repo owner/name] [--json]" >&2; exit 2; }
case "$PR" in *[!0-9]*) echo "PR must be a number: $PR" >&2; exit 2 ;; esac

FIX="${CI_VERDICT_FIXTURE_DIR:-}"
HEAD=""

emit() { # verdict reason [contexts-json]
  if [ "$JSON" = 1 ]; then
    jq -nc --arg v "$1" --arg r "$2" --arg p "$PR" --arg h "$HEAD" --argjson c "${3:-[]}" \
      '{verdict:$v, reason:$r, pr:$p, head_sha:$h, contexts:$c}'
  else
    printf '%s %s\n' "$1" "$2"
  fi
}
indeterminate() { emit INDETERMINATE "$1"; exit 3; }

command -v jq >/dev/null 2>&1 || { echo "INDETERMINATE jq not on PATH" >&2; exit 3; }

if [ -n "$FIX" ]; then
  [ -d "$FIX" ] || indeterminate "fixture dir not found: $FIX"
  read_pr()       { cat "$FIX/pr.json" 2>/dev/null; }
  read_pr_after() { if [ -f "$FIX/pr-after.json" ]; then cat "$FIX/pr-after.json"; else read_pr; fi; }
  read_rules()    { cat "$FIX/rules.json" 2>/dev/null; }
  read_branch()   { if [ -f "$FIX/branch.json" ]; then cat "$FIX/branch.json"; else echo '{}'; fi; }
  read_runs()     { cat "$FIX/check-runs.json" 2>/dev/null; }
  read_statuses() { if [ -f "$FIX/statuses.json" ]; then cat "$FIX/statuses.json"; else echo '[]'; fi; }
else
  command -v gh >/dev/null 2>&1 || indeterminate "gh not on PATH"
  if [ -z "$REPO" ]; then
    REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" \
      || indeterminate "cannot resolve repo; pass --repo"
  fi
  read_pr()       { gh pr view "$PR" --repo "$REPO" --json headRefOid,baseRefName 2>/dev/null; }
  read_pr_after() { read_pr; }
  read_rules()    { gh api "repos/$REPO/rules/branches/$1" 2>/dev/null; }
  read_branch()   { gh api "repos/$REPO/branches/$1" 2>/dev/null; }
  # Actions jobs at the head, as check-run-shaped rows of the Actions app (15368). Not the
  # check-runs API: a fine-grained PAT cannot hold Checks permission (dev-box, 2026-10-29).
  # A run with no jobs yet adds a placeholder that matches no context but counts as running.
  # Payloads go through stdin, never argv: one private repo's head run list was 177 KB, over Linux's
  # 128 KB limit on a single argument, and jq --argjson failed with E2BIG (dev-box, 2026-10-29).
  read_runs() {
    local runs id one jobs=""
    runs="$(gh api --paginate --slurp "repos/$REPO/actions/runs?head_sha=$HEAD&per_page=100" 2>/dev/null \
      | jq -c '[ .[].workflow_runs[] | {id, name, status} ]')" && [ -n "$runs" ] || return 1
    for id in $(jq -r '.[].id' <<<"$runs"); do
      one="$(gh api --paginate --slurp "repos/$REPO/actions/runs/$id/jobs?filter=latest&per_page=100" \
        2>/dev/null | jq -c --argjson rid "$id" \
          '{rid: $rid, jobs: [ .[].jobs[] | {id, name, status, conclusion, completed_at} ]}')" \
        && [ -n "$one" ] || return 1
      jobs+="$one"$'\n'
    done
    # Input: the run list, then one {rid, jobs} object per run.
    printf '%s\n%s' "$runs" "$jobs" | jq -cs '
      .[0] as $runs
      | [ .[1:][] as $r | ($runs[] | select(.id == $r.rid)) as $run
          | if ($r.jobs | length) == 0 and ($run.status // "") != "completed"
            then {id: 0, name: ("run: " + ($run.name // "?")), status: $run.status,
                  conclusion: null, app: {id: 15368}}
            else $r.jobs[] + {app: {id: 15368}} end ]'
  }
  read_statuses() { gh api --paginate "repos/$REPO/commits/$HEAD/status?per_page=100" \
                      --jq '.statuses' 2>/dev/null | jq -s 'add // []'; }
fi

PRJ="$(read_pr)" || indeterminate "cannot read PR #$PR"
HEAD="$(jq -r '.headRefOid // empty' <<<"$PRJ" 2>/dev/null)"
BASE="$(jq -r '.baseRefName // empty' <<<"$PRJ" 2>/dev/null)"
[[ "$HEAD" =~ ^[0-9a-f]{40}$ ]] || indeterminate "PR #$PR head SHA unreadable"
[ -n "$BASE" ] || indeterminate "PR #$PR base branch unreadable"

RULES="$(read_rules "$BASE")" || indeterminate "cannot read rulesets for $BASE"
BRANCH="$(read_branch "$BASE")" || indeterminate "cannot read branch protection for $BASE"
REQUIRED="$(jq -nc --argjson rules "$RULES" --argjson branch "$BRANCH" '
  ( [ $rules[] | select(.type == "required_status_checks")
        | .parameters.required_status_checks[]
        | {context, integration_id: (.integration_id // null)} ]
  + [ ($branch.protection.required_status_checks.checks // [])[]
        | {context, integration_id: (if (.app_id // -1) < 0 then null else .app_id end)} ]
  ) | unique' 2>/dev/null)" \
  || indeterminate "rulesets or branch payload for $BASE is malformed"
[ "$(jq 'length' <<<"$REQUIRED")" -gt 0 ] \
  || indeterminate "no required status checks in any ruleset or classic protection on $BASE — 'all required passed' would be vacuous; use ci-evidence.sh"

RUNS="$(read_runs)" || indeterminate "cannot read check runs at ${HEAD:0:12}"
STATUSES="$(read_statuses)" || indeterminate "cannot read commit statuses at ${HEAD:0:12}"
jq -e 'type == "array"' <<<"$RUNS" >/dev/null 2>&1 || indeterminate "check runs payload is not an array"
jq -e 'type == "array"' <<<"$STATUSES" >/dev/null 2>&1 || indeterminate "statuses payload is not an array"

# One row per required context: {context, state} with state in pass|fail|running|missing.
ROWS="$(jq -c --argjson runs "$RUNS" --argjson sts "$STATUSES" '
  def run_state:
    if (.status // "" | ascii_downcase) != "completed" then "running"
    elif (.conclusion // "" | ascii_downcase) as $c
         | ["success", "neutral", "skipped"] | index($c) then "pass"
    else "fail" end;
  def status_state:
    (.state // "" | ascii_downcase) as $s
    | if $s == "success" then "pass" elif $s == "pending" then "running" else "fail" end;
  map(. as $req
      | ([ $runs[] | select(.name == $req.context)
                   | select($req.integration_id == null or (.app.id // null) == $req.integration_id) ]
         | max_by(.id)) as $run
      | ([ $sts[] | select($req.integration_id == null and .context == $req.context) ]
         | max_by(.id // 0)) as $st
      | { context: $req.context,
          state: (if $run != null then ($run | run_state)
                  elif $st != null then ($st | status_state)
                  elif $req.integration_id != null and $req.integration_id != 15368 then "unobservable"
                  elif $req.integration_id == null then "unmapped"
                  else "missing" end) })' <<<"$REQUIRED")" \
  || indeterminate "could not evaluate required contexts"

# Anything at all still running at this head — required or not. Its downstream jobs may not
# exist yet, so a missing required context is not final while this is true.
ANY_RUNNING="$(jq -r --argjson sts "$STATUSES" '
  (any(.[]; (.status // "" | ascii_downcase) != "completed"))
  or (any($sts[]; (.state // "" | ascii_downcase) == "pending"))' <<<"$RUNS")"

AFTER="$(read_pr_after | jq -r '.headRefOid // empty' 2>/dev/null)"
[ "$AFTER" = "$HEAD" ] || indeterminate "head moved during evaluation (${HEAD:0:12} -> ${AFTER:0:12}); re-run"

names() { jq -r --arg s "$1" '[.[] | select(.state == $s) | .context] | join(", ")' <<<"$ROWS"; }
count() { jq -r --arg s "$1" '[.[] | select(.state == $s)] | length' <<<"$ROWS"; }
TOTAL="$(jq 'length' <<<"$ROWS")"
AT="at ${HEAD:0:12} (base $BASE)"

if [ "$(count fail)" -gt 0 ]; then
  emit FAILED "$(names fail) $AT" "$ROWS"; exit 1
fi
if [ "$(count running)" -gt 0 ]; then
  emit PENDING "$(count running) of $TOTAL required context(s) running: $(names running) $AT" "$ROWS"; exit 1
fi
if [ "$(( $(count missing) + $(count unmapped) ))" -gt 0 ] && [ "$ANY_RUNNING" = true ]; then
  emit PENDING "$(( $(count missing) + $(count unmapped) )) of $TOTAL required context(s) not created yet while other runs are in flight: $(jq -r '[.[] | select(.state == "missing" or .state == "unmapped") | .context] | join(", ")' <<<"$ROWS") $AT" "$ROWS"; exit 1
fi
if [ "$(count unobservable)" -gt 0 ]; then
  emit INDETERMINATE "required context(s) owned by a non-Actions app cannot be read without Checks permission: $(names unobservable) $AT" "$ROWS"; exit 3
fi
if [ "$(count unmapped)" -gt 0 ]; then
  emit INDETERMINATE "no Actions job or commit status matches required context(s) $(names unmapped) $AT — a non-Actions check run cannot be read without Checks permission" "$ROWS"; exit 3
fi
if [ "$(count missing)" -gt 0 ]; then
  emit UNTRIGGERED "$(count missing) required contexts have no run: $(names missing) $AT — stale branch: rebase onto $BASE; Actions outage: wait (githubstatus.com); never --admin" "$ROWS"; exit 1
fi
emit GREEN "$TOTAL of $TOTAL required context(s) passed: $(names pass) $AT" "$ROWS"
exit 0
