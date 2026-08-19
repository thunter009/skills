#!/usr/bin/env bash
# Tests for ci-evidence.sh — the merge gate's "did CI actually run" leg.
#
# MUTATION-FIRST, same bar as test_review_evidence.sh: a guard that only ever returns CI_RAN
# on a healthy PR is indistinguishable from `exit 0`. Every case below forces a specific wrong
# state and asserts the guard notices. The healthy cases are last.
#
# The wrong states are not invented — each one is a finding from the adversarial review of
# this script (agent-skills #239), including the three that made the first draft unsafe:
# `--min 0` disabling the guard, non-CI runs counting as evidence, and in-flight runs being
# accepted (which raced the green leg).
#
# Hermetic: no network. Fixture shapes are trimmed from REAL `gh pr view --json
# statusCheckRollup` payloads — a private repo's #1608 (the PR that merged untested) and #1597 (healthy).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(cd "$HERE/.." && pwd)"
GUARD="$SKILL/scripts/ci-evidence.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ci-evidence-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1" >&2; }
expect() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
contains() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in '$1')" ;; esac; }

run() { # fixture-dir [args...] -> OUT, RC
  local d="$1"; shift
  OUT="$(CI_EVIDENCE_FIXTURE_DIR="$d" bash "$GUARD" 999 "$@" 2>&1)"; RC=$?
}
mkfix() { # name  rollup.json
  local d="$TMP/$1"; mkdir -p "$d"
  [ $# -ge 2 ] && printf '%s' "$2" > "$d/rollup.json"
  echo "$d"
}

# A GitHub Actions check entry. $1 name, $2 status, $3 conclusion, $4 run id.
act() { printf '{"__typename":"CheckRun","name":"%s","status":"%s","conclusion":%s,"detailsUrl":"https://github.com/o/r/actions/runs/%s/job/9"}' "$1" "$2" "$3" "$4"; }
# A third-party app check (CodeRabbit shape): no /actions/runs/ URL.
app() { printf '{"__typename":"CheckRun","name":"%s","status":"COMPLETED","conclusion":"SUCCESS","detailsUrl":"https://app.coderabbit.ai/reviews/1"}' "$1"; }

# PR #1608 as GitHub actually reported it: one entry, all fields null, zero Actions runs.
SLIPPED='[{"__typename":"CheckRun","name":null,"status":null,"conclusion":null,"detailsUrl":""}]'
ONLY_APP="[$(app CodeRabbit)]"
HEALTHY="[$(act CI COMPLETED '"SUCCESS"' 111),$(act "Semantic Gate" COMPLETED '"SUCCESS"' 222),$(act commit-lint COMPLETED '"SUCCESS"' 333)]"
RERUNS="[$(act CI COMPLETED '"SUCCESS"' 111),$(act CI COMPLETED '"SUCCESS"' 111),$(act CI COMPLETED '"SUCCESS"' 111)]"
INFLIGHT="[$(act CI IN_PROGRESS null 111),$(act "Semantic Gate" QUEUED null 222)]"
SKIPPED="[$(act CI COMPLETED '"SKIPPED"' 111),$(act Preview COMPLETED '"CANCELLED"' 222)]"
FAILING="[$(act CI COMPLETED '"FAILURE"' 111)]"
QUOTED="[$(act 'CI \"required\"' COMPLETED '"SUCCESS"' 111)]"

echo "== ci-evidence.sh"

# ── 1. The hole this exists to close ─────────────────────────────────────
run "$(mkfix slipped "$SLIPPED")"
expect "$RC" 1 "PR #1608 shape (no Actions runs) => CI_ABSENT"
run "$(mkfix onlyapp "$ONLY_APP")"
expect "$RC" 1 "only a third-party app check => CI_ABSENT"
contains "$OUT" "not evidence that CI ran" "explains why an app check does not count"
run "$(mkfix empty "[]")"
expect "$RC" 1 "no checks at all => CI_ABSENT"

# ── 2. HIGH from review: --min 0 silently disabled the whole guard ───────
OUT="$(CI_EVIDENCE_FIXTURE_DIR="$(mkfix z "$SLIPPED")" bash "$GUARD" 999 --min 0 2>&1)"; RC=$?
expect "$RC" 2 "--min 0 => usage error, never a pass"
contains "$OUT" "disable the guard" "says why 0 is refused"

# ── 3. HIGH from review: in-flight runs must NOT count ───────────────────
# Accepting them raced the green leg: it read the rollup before the run appeared, this leg
# read it after, and both passed on a PR nothing had validated.
run "$(mkfix inflight "$INFLIGHT")"
expect "$RC" 1 "queued/in-progress runs => CI_ABSENT (not yet evidence)"

# ── 4. HIGH from review: retries of ONE workflow must not satisfy --min ──
run "$(mkfix reruns "$RERUNS")" --min 3
expect "$RC" 1 "3 re-runs of one workflow with --min 3 => CI_ABSENT (distinct runs)"
run "$(mkfix reruns2 "$RERUNS")"
expect "$RC" 0 "...but one distinct run still satisfies --min 1"

# ── 5. Skipped / cancelled validated nothing ─────────────────────────────
run "$(mkfix skipped "$SKIPPED")"
expect "$RC" 1 "all runs skipped/cancelled => CI_ABSENT"

# ── 6. Failing CI still RAN — greenness is leg 3's question, not this one ─
run "$(mkfix failing "$FAILING")"
expect "$RC" 0 "a FAILURE conclusion => CI_RAN (leg 3 refuses it, not leg 4)"

# ── 7. Indeterminate is never a pass ─────────────────────────────────────
run "$(mkfix badpayload '{"message":"Not Found"}')"
expect "$RC" 3 "non-array payload => INDETERMINATE"
run "$(mkfix notjson 'not json at all')"
expect "$RC" 3 "unparseable payload => INDETERMINATE"
OUT="$(CI_EVIDENCE_FIXTURE_DIR=/nonexistent bash "$GUARD" 999 2>&1)"; RC=$?
expect "$RC" 3 "missing fixture dir => INDETERMINATE"

# ── 8. LOW from review: a trailing flag must not spin forever ────────────
OUT="$(timeout 10 bash "$GUARD" 999 --repo 2>&1)"; RC=$?
expect "$RC" 2 "trailing --repo => usage error, not an infinite loop"
OUT="$(timeout 10 bash "$GUARD" 999 --min 2>&1)"; RC=$?
expect "$RC" 2 "trailing --min => usage error, not an infinite loop"
OUT="$(bash "$GUARD" 2>&1)"; RC=$?
expect "$RC" 2 "no PR number => usage error"
OUT="$(bash "$GUARD" 999 --min nope 2>&1)"; RC=$?
expect "$RC" 2 "non-numeric --min => usage error"

# ── 9. LOW from review: --json must stay valid JSON ──────────────────────
run "$(mkfix quoted "$QUOTED")" --json
expect "$RC" 0 "workflow name containing quotes => CI_RAN"
if echo "$OUT" | jq -e . >/dev/null 2>&1; then
  ok "--json output parses with a quoted workflow name"
else
  bad "--json output is invalid JSON: $OUT"
fi

# ── 10. Healthy PRs are not disturbed ────────────────────────────────────
run "$(mkfix healthy "$HEALTHY")"
expect "$RC" 0 "healthy PR => CI_RAN"
contains "$OUT" "Semantic Gate" "names the workflows that ran"
run "$(mkfix healthy2 "$HEALTHY")" --min 3
expect "$RC" 0 "3 distinct runs with --min 3 => CI_RAN"
run "$(mkfix healthy3 "$HEALTHY")" --min 4
expect "$RC" 1 "3 distinct runs with --min 4 => CI_ABSENT"
run "$(mkfix mixed "[$(act CI COMPLETED '"SUCCESS"' 111),$(act Preview COMPLETED '"SKIPPED"' 222),$(app CodeRabbit)]")"
expect "$RC" 0 "one real run alongside a skip and an app check => CI_RAN"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
