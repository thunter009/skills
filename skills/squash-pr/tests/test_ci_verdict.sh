#!/usr/bin/env bash
# Tests for ci-verdict.sh — "is every REQUIRED context green at the exact head".
#
# MUTATION-FIRST, same bar as test_ci_evidence.sh: a guard that only returns GREEN on a
# healthy PR is indistinguishable from `exit 0`. Each wrong state below is one a real loop
# reported as green. The healthy cases are last.
#
# Hermetic: no network. Shapes are trimmed from REAL payloads — `rules/branches/dev` and
# `commits/<sha>/check-runs` on thunter009/agent-skills (PR #511, 2026-10-08).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(cd "$HERE/.." && pwd)"
GUARD="$SKILL/scripts/ci-verdict.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ci-verdict-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1" >&2; }
expect() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
contains() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in '$1')" ;; esac; }

SHA=e7d1e219e8e583d701018b831ef7f77fa7dfb779
NEW=1111111111111111111111111111111111111111
PRJ="{\"headRefOid\":\"$SHA\",\"baseRefName\":\"dev\"}"
# A ruleset requiring the given contexts, pinned to the GitHub Actions app (15368).
rules() {
  local items="" c
  for c in "$@"; do items="$items${items:+,}{\"context\":\"$c\",\"integration_id\":15368}"; done
  printf '[{"type":"required_status_checks","parameters":{"required_status_checks":[%s]}},{"type":"non_fast_forward"}]' "$items"
}
# A check run. $1 id, $2 name, $3 status, $4 conclusion (json), $5 app id (default 15368).
cr() { printf '{"id":%s,"name":"%s","status":"%s","conclusion":%s,"app":{"id":%s}}' "$1" "$2" "$3" "$4" "${5:-15368}"; }
CODERABBIT_STATUS='[{"id":1,"context":"CodeRabbit","state":"success"}]'

run() { # dir [args...] -> OUT, RC
  local d="$1"; shift
  OUT="$(CI_VERDICT_FIXTURE_DIR="$d" bash "$GUARD" 999 "$@" 2>&1)"; RC=$?
}
mkfix() { # name rules check-runs [statuses] [pr-after]
  local d="$TMP/$1"; mkdir -p "$d"
  printf '%s' "$PRJ" > "$d/pr.json"
  printf '%s' "$2" > "$d/rules.json"
  printf '%s' "$3" > "$d/check-runs.json"
  [ $# -ge 4 ] && printf '%s' "$4" > "$d/statuses.json"
  [ $# -ge 5 ] && printf '%s' "$5" > "$d/pr-after.json"
  echo "$d"
}

echo "== ci-verdict.sh"

# ── 1. The hole this exists to close: zero runs, one green app status ─────
# PR #2284 (Actions outage) / #1366 (stale branch): only CodeRabbit reported, nothing pending.
run "$(mkfix zero "$(rules verify lint)" '[]' "$CODERABBIT_STATUS")"
expect "$RC" 1 "zero runs + green CodeRabbit status => not green"
contains "$OUT" "UNTRIGGERED 2 required contexts have no run" "zero runs => UNTRIGGERED with count"
contains "$OUT" "never --admin" "names the remedy split and forbids --admin"

# ── 2. Required aggregator never created, rest finished => UNTRIGGERED ────
run "$(mkfix partial "$(rules verify aggregate)" "[$(cr 10 verify completed '"success"')]")"
expect "$RC" 1 "one required context missing on a quiet head => exit 1"
contains "$OUT" "UNTRIGGERED 1 required contexts have no run: aggregate" "names the missing context"

# ── 3. Missing while upstream still runs => PENDING, not UNTRIGGERED ──────
# PR #2912: backend-verified uncreated while backend-unit sat QUEUED for 43 minutes.
run "$(mkfix needs "$(rules verify aggregate)" "[$(cr 10 verify completed '"success"'),$(cr 11 unit queued null)]")"
expect "$RC" 1 "missing required + unrelated run in flight => exit 1"
contains "$OUT" "PENDING" "missing-while-running => PENDING"
contains "$OUT" "not created yet" "says the context is not created yet"

# ── 4. A required context running => PENDING ──────────────────────────────
run "$(mkfix running "$(rules verify)" "[$(cr 10 verify in_progress null)]")"
expect "$RC" 1 "required in_progress => exit 1"
contains "$OUT" "PENDING 1 of 1 required context(s) running: verify" "running => PENDING"

# ── 5. FAILED, and failure outranks everything else ──────────────────────
run "$(mkfix failed "$(rules verify lint)" "[$(cr 10 verify completed '"failure"'),$(cr 11 lint completed '"cancelled"')]")"
expect "$RC" 1 "failure => exit 1"
contains "$OUT" "FAILED lint, verify" "lists every failed context (cancelled counts)"
run "$(mkfix failfirst "$(rules verify lint gone)" "[$(cr 10 verify completed '"failure"'),$(cr 11 lint queued null)]")"
contains "$OUT" "FAILED verify" "FAILED outranks PENDING and missing"

# ── 6. Latest run per context wins ───────────────────────────────────────
run "$(mkfix rerun "$(rules verify)" "[$(cr 10 verify completed '"failure"'),$(cr 20 verify completed '"success"')]")"
expect "$RC" 0 "red run re-run green => GREEN"
run "$(mkfix rerunred "$(rules verify)" "[$(cr 20 verify completed '"success"'),$(cr 30 verify completed '"failure"')]")"
expect "$RC" 1 "green run re-run red => not green"

# ── 7. A same-named check from another app is not the required one ───────
run "$(mkfix wrongapp "$(rules verify)" "[$(cr 10 verify completed '"success"' 999)]")"
expect "$RC" 1 "same name, wrong integration_id => not green"
contains "$OUT" "UNTRIGGERED" "wrong-app check counts as missing"

# ── 8. Commit statuses: only for unpinned rules ──────────────────────────
run "$(mkfix status "$(rules CodeRabbit)" '[]' "$CODERABBIT_STATUS")"
expect "$RC" 1 "commit status cannot satisfy an app-pinned rule"
run "$(mkfix status2 '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"legacy"}]}}]' '[]' '[{"id":5,"context":"legacy","state":"pending"}]')"
contains "$OUT" "PENDING" "pending commit status => PENDING"

# ── 9. INDETERMINATE is never a pass ─────────────────────────────────────
run "$(mkfix norules '[{"type":"non_fast_forward"}]' "[$(cr 10 verify completed '"success"')]")"
expect "$RC" 3 "no required contexts => INDETERMINATE (vacuous otherwise)"
contains "$OUT" "vacuous" "explains why an empty required set is refused"
run "$(mkfix moved "$(rules verify)" "[$(cr 10 verify completed '"success"')]" '[]' "{\"headRefOid\":\"$NEW\",\"baseRefName\":\"dev\"}")"
expect "$RC" 3 "head moved during evaluation => INDETERMINATE"
run "$(mkfix badruns "$(rules verify)" '{"message":"Not Found"}')"
expect "$RC" 3 "non-array check runs => INDETERMINATE"
run "$(mkfix badrules 'not json' '[]')"
expect "$RC" 3 "unparseable rulesets => INDETERMINATE"
D="$(mkfix badhead "$(rules verify)" '[]')"; printf '{"headRefOid":"nope","baseRefName":"dev"}' > "$D/pr.json"
run "$D"
expect "$RC" 3 "malformed head SHA => INDETERMINATE"
OUT="$(CI_VERDICT_FIXTURE_DIR=/nonexistent bash "$GUARD" 999 2>&1)"; RC=$?
expect "$RC" 3 "missing fixture dir => INDETERMINATE"

# ── 9b. Classic branch protection is a required-context source ───────────
# /rules/branches/ returns [] under classic protection (probe 2026-09-15).
D="$(mkfix classic '[]' "[$(cr 10 verify completed '"failure"')]")"
printf '{"protection":{"required_status_checks":{"checks":[{"context":"verify","app_id":15368}]}}}' > "$D/branch.json"
run "$D"
expect "$RC" 1 "classic-only required check failing => not green"
contains "$OUT" "FAILED verify" "classic required context is evaluated"
D="$(mkfix classicany '[]' "[$(cr 10 verify completed '"success"' 999)]")"
printf '{"protection":{"required_status_checks":{"checks":[{"context":"verify","app_id":-1}]}}}' > "$D/branch.json"
run "$D"
expect "$RC" 0 "classic app_id -1 => any app satisfies it"
D="$(mkfix badbranch "$(rules verify)" "[$(cr 10 verify completed '"success"')]")"
printf 'not json' > "$D/branch.json"
run "$D"
expect "$RC" 3 "unparseable branch payload => INDETERMINATE"

# ── 10. Usage ────────────────────────────────────────────────────────────
OUT="$(bash "$GUARD" 2>&1)"; RC=$?
expect "$RC" 2 "no PR number => usage error"
OUT="$(timeout 10 bash "$GUARD" 999 --repo 2>&1)"; RC=$?
expect "$RC" 2 "trailing --repo => usage error"
OUT="$(bash "$GUARD" 12x 2>&1)"; RC=$?
expect "$RC" 2 "non-numeric PR => usage error"

# ── 11. Healthy PRs are GREEN ────────────────────────────────────────────
# PR #511's real shape: verify ran twice, plus an unrequired no-merge-commits and CodeRabbit.
HEALTHY="[$(cr 113435526053 no-merge-commits completed '"success"'),$(cr 113435526037 verify completed '"success"'),$(cr 113435525504 verify completed '"success"')]"
run "$(mkfix healthy "$(rules verify)" "$HEALTHY" "$CODERABBIT_STATUS")"
expect "$RC" 0 "PR #511 shape => GREEN"
contains "$OUT" "GREEN 1 of 1 required context(s) passed: verify at e7d1e219e8e5" "GREEN names contexts and pins the head"
run "$(mkfix skipped "$(rules verify lint)" "[$(cr 10 verify completed '"success"'),$(cr 11 lint completed '"skipped"')]")"
expect "$RC" 0 "skipped/neutral required context => GREEN (GitHub treats it as passing)"
run "$(mkfix json "$(rules verify)" "$HEALTHY")" --json
if jq -e --arg h "$SHA" '.verdict == "GREEN" and .head_sha == $h and (.contexts | length) == 1' <<<"$OUT" >/dev/null 2>&1; then
  ok "--json carries verdict, head and per-context rows"
else
  bad "--json output wrong: $OUT"
fi

# ── 12. What a token without Checks permission cannot see ───────────────
# A fine-grained PAT cannot hold Checks permission, so the live path reads Actions jobs
# (dev-box, 2026-10-29). A required context it cannot observe is never GREEN or UNTRIGGERED.
UNPINNED='[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"verify"},{"context":"third-party"}]}}]'
run "$(mkfix unmapped "$UNPINNED" "[$(cr 10 verify completed '"success"')]" '[]')"
expect "$RC" 3 "unpinned required context with no job and no status => INDETERMINATE"
contains "$OUT" "third-party" "INDETERMINATE names the unmapped context"
run "$(mkfix unmapped-running "$UNPINNED" "[$(cr 10 verify in_progress null)]" '[]')"
expect "$RC" 1 "unmapped while another run is in flight => PENDING (exit 1)"
contains "$OUT" "PENDING" "unmapped context waits while runs are in flight"
OTHERAPP='[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"verify","integration_id":15368},{"context":"scan","integration_id":999}]}}]'
run "$(mkfix unobservable "$OTHERAPP" "[$(cr 10 verify completed '"success"')]" '[]')"
expect "$RC" 3 "required context pinned to a non-Actions app => INDETERMINATE"
contains "$OUT" "non-Actions app" "INDETERMINATE says why it cannot see the context"
run "$(mkfix unobservable-red "$OTHERAPP" "[$(cr 10 verify completed '"failure"')]" '[]')"
expect "$RC" 1 "a visible failure still outranks an unobservable context"

# ── 13. Live path reads Actions runs and jobs, never the Checks API ───────
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in *statusCheckRollup*|*check-runs*) echo "Checks API called: $*" >&2; exit 97 ;; esac
case "$*" in
  "pr view"*) printf '{"headRefOid":"%s","baseRefName":"dev"}\n' "$FAKE_HEAD" ;;
  "api repos/o/r/rules/branches/dev") printf '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"verify","integration_id":15368},{"context":"merge-policy"}]}}]\n' ;;
  "api repos/o/r/branches/dev") echo '{}' ;;
  *"actions/runs?head_sha="*) pad=""; [ -n "${FAKE_PAD:-}" ] && pad="$(head -c 200000 /dev/zero | tr '\0' a)"
    printf '[{"workflow_runs":[{"id":11,"name":"CI","status":"completed","pad":"%s"},{"id":12,"name":"Later","status":"%s"}]}]\n' "$pad" "${FAKE_RUN12:-completed}" ;;
  *"actions/runs/11/jobs"*) printf '[{"jobs":[{"id":101,"name":"verify","status":"completed","conclusion":"%s","completed_at":"2026-10-29T00:00:00Z"}]}]\n' "${FAKE_VERIFY:-success}" ;;
  *"actions/runs/12/jobs"*) echo '[{"jobs":[]}]' ;;
  *"commits/"*"/status"*) echo '[{"id":7,"context":"merge-policy","state":"success"}]' ;;  # read_statuses passes --jq .statuses
  *) echo "unexpected gh call: $*" >&2; exit 64 ;;
esac
EOF
chmod +x "$TMP/bin/gh"
OUT="$(FAKE_HEAD=$SHA PATH="$TMP/bin:$PATH" bash "$GUARD" 999 --repo o/r 2>&1)"; RC=$?
expect "$RC" 0 "live path: Actions job + commit status satisfy the required contexts => GREEN"
OUT="$(FAKE_HEAD=$SHA FAKE_VERIFY=failure PATH="$TMP/bin:$PATH" bash "$GUARD" 999 --repo o/r 2>&1)"; RC=$?
expect "$RC" 1 "live path: a failed Actions job => FAILED"
contains "$OUT" "FAILED verify" "live path names the failed job"
OUT="$(FAKE_HEAD=$SHA FAKE_RUN12=queued PATH="$TMP/bin:$PATH" bash "$GUARD" 999 --repo o/r 2>&1)"; RC=$?
expect "$RC" 0 "a queued run with no jobs does not block passed required contexts"
# One private repo's head run list was 177 KB; jq --argjson hit Linux's 128 KB argv limit (2026-10-29).
OUT="$(FAKE_HEAD=$SHA FAKE_PAD=1 PATH="$TMP/bin:$PATH" bash "$GUARD" 999 --repo o/r 2>&1)"; RC=$?
expect "$RC" 0 "a run list over 128 KB still reads: payloads never ride argv"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
