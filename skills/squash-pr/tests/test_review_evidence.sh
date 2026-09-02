#!/usr/bin/env bash
# Tests for review-evidence.sh — the merge gate's review leg.
#
# MUTATION-FIRST, same bar as tests/test_loop_preflight.sh in atrium-loops: a guard that only
# ever returns REVIEWED on a healthy PR is indistinguishable from `exit 0`. Every case below
# forces a specific wrong state and asserts the guard notices. The healthy case is last.
#
# Hermetic: no network. Fixtures are trimmed from REAL GitHub payloads (the PR numbers in the
# names are the ones they came from), so the shapes are genuine rather than invented.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(cd "$HERE/.." && pwd)"
GUARD="$SKILL/scripts/review-evidence.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/review-evidence-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1" >&2; }
expect() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

run() { # fixture-dir -> sets OUT, RC
  OUT="$(REVIEW_EVIDENCE_FIXTURE_DIR="$1" bash "$GUARD" 999 2>&1)"; RC=$?
}

mkfix() { # name  head  reviews.json  [issue_comments.json]
  local d="$TMP/$1"; mkdir -p "$d"
  printf '%s' "$2" > "$d/head.txt"
  printf '%s' "$3" > "$d/reviews.json"
  [ $# -ge 4 ] && printf '%s' "$4" > "$d/issue_comments.json"
  echo "$d"
}

HEAD=99d43c88aa11bb22cc33dd44ee55ff6677889900
OLD=23e88984ffeeddccbbaa99887766554433221100
# 245 chars, carries a real file:line. The floor is 200: on 2026-09-01 a 126-char template
# cleared the old 40-char floor on four PRs in three seconds.
BODY='Review: 1 issue (0 critical, 1 informational). INFORMATIONAL (non-blocking): scripts/reconcile.py:40 catches bare Exception, so a KeyboardInterrupt during the reconcile loop is swallowed and the run reports success. Narrow the except to OSError.'

# The exact body posted on four PRs on 2026-09-01. Verdict, four sections, nothing said.
TEMPLATE='## Review — 4 file(s) read 4 changed\n**Verdict: APPROVE**\nHIGH: None\nMEDIUM\nNIT: None\nNot reviewed: none'

# Same emptiness, past the 200-char floor and in the documented multi-line section shape.
# A length floor alone cannot see the difference; the shape check can.
PADDED='## Review — 12 file(s) read of 12 changed, every changed line inspected with care across the whole of this pull request\n**Verdict: APPROVE**\n**HIGH**\n- None.\n**MEDIUM / NIT**\n- None.\n**Not reviewed:** none'

# A clean PR that really was read: per-file lines plus three named checks, no findings.
FILES_BODY='## Review — 2 file(s) read of 2 changed\n\n**Head reviewed:** `99d43c88`\n\n**Verdict: APPROVE**\n\n### Files\n- `scripts/lib/inventory.py` — checked the dedup key and the empty-input branch\n- `tests/test_inventory.py` — checked the fixture covers the duplicate-slug case\n\n**HIGH**\n- None.\n\n**No findings after checking:** null handling in build_inventory, test coverage for duplicate slugs, no network calls in the scanner\n\n**Not reviewed:** none'

CR_LIMIT='[{"user":{"login":"coderabbitai[bot]"},"body":"> [!WARNING]\n> ## Review limit reached\n> you have reached your PR review limit, so we could not start this review."}]'
CR_SKIP='[{"user":{"login":"coderabbitai[bot]"},"body":"> [!IMPORTANT]\n> ## Review skipped\n> Auto reviews are disabled on base branches other than the default branch."}]'

echo "== review-evidence.sh"

# 1. The live hole this guard exists to close: green CodeRabbit check, zero review bodies.
#    A private repo's #1631 and agent-skills #217 were both in exactly this state on 2026-08-11.
run "$(mkfix no-review "$HEAD" '[]' "$CR_LIMIT")"
expect "$RC" 1 "rate-limited CodeRabbit + no reviews => UNREVIEWED"
case "$OUT" in *"rate-limited"*) ok "reports WHY CodeRabbit was absent" ;;
               *) bad "should name the rate limit: $OUT" ;; esac

run "$(mkfix skipped "$HEAD" '[]' "$CR_SKIP")"
expect "$RC" 1 "base-branch-skipped CodeRabbit + no reviews => UNREVIEWED"

# 2. A review of code that is no longer the code being merged.
run "$(mkfix stale "$HEAD" "[{\"state\":\"COMMENTED\",\"commit_id\":\"$OLD\",\"body\":\"$BODY\"}]")"
expect "$RC" 1 "substantive review at an OLDER commit => UNREVIEWED"
case "$OUT" in *"none at head"*) ok "names staleness as the reason" ;;
               *) bad "should say the review is not at head: $OUT" ;; esac

# 3. Rubber-stamps are not reviews.
run "$(mkfix short "$HEAD" "[{\"state\":\"APPROVED\",\"commit_id\":\"$HEAD\",\"body\":\"lgtm\"}]")"
expect "$RC" 1 "4-char approval body => UNREVIEWED"

# 4. A queued-but-unsubmitted review must not count.
run "$(mkfix pending "$HEAD" "[{\"state\":\"PENDING\",\"commit_id\":\"$HEAD\",\"body\":\"$BODY\"}]")"
expect "$RC" 1 "PENDING review => UNREVIEWED"

# 5. INDETERMINATE (3) is its own answer and must never read as a pass.
run "$TMP/does-not-exist"
expect "$RC" 3 "missing fixture dir => INDETERMINATE"

run "$(mkfix malformed "$HEAD" '{"message":"Not Found"}')"
expect "$RC" 3 "API error object instead of an array => INDETERMINATE"

run "$(mkfix nohead "" "[{\"state\":\"COMMENTED\",\"commit_id\":\"$HEAD\",\"body\":\"$BODY\"}]")"
expect "$RC" 3 "unknown head SHA => INDETERMINATE"

# 5b. The template hole this change closes. A body can be well-formed and say nothing:
#     verdict present, every section None, no file named, no line cited.
run "$(mkfix template "$HEAD" "[{\"state\":\"APPROVED\",\"commit_id\":\"$HEAD\",\"body\":\"$TEMPLATE\"}]")"
expect "$RC" 1 "template-only body (None/None/none) => UNREVIEWED"
case "$OUT" in *"template-only review body"*) ok "names the template as the reason" ;;
               *) bad "should say template-only: $OUT" ;; esac

run "$(mkfix padded "$HEAD" "[{\"state\":\"APPROVED\",\"commit_id\":\"$HEAD\",\"body\":\"$PADDED\"}]")"
expect "$RC" 1 "template padded past the 200-char floor => UNREVIEWED"
case "$OUT" in *"template-only review body"*) ok "length does not launder a template" ;;
               *) bad "padded template should still read as a template: $OUT" ;; esac

# 5c. A real review that happens to be under the new floor is still not evidence.
run "$(mkfix under-floor "$HEAD" "[{\"state\":\"APPROVED\",\"commit_id\":\"$HEAD\",\"body\":\"Read both files. The retry path at api/client.ts:88 looks right to me and the tests cover it.\"}]")"
expect "$RC" 1 "94-char body with a file:line => UNREVIEWED (under the 200 floor)"

# 6. Healthy, deliberately last. A private repo's #1628: real loop review at head, CodeRabbit rate-limited.
run "$(mkfix healthy "$HEAD" "[{\"state\":\"COMMENTED\",\"commit_id\":\"$HEAD\",\"body\":\"$BODY\"}]" "$CR_LIMIT")"
expect "$RC" 0 "substantive review at head => REVIEWED (despite rate-limited CodeRabbit)"

# 7. CHANGES_REQUESTED is evidence a review HAPPENED; blocking is a different gate leg.
run "$(mkfix changes "$HEAD" "[{\"state\":\"CHANGES_REQUESTED\",\"commit_id\":\"$HEAD\",\"body\":\"$BODY\"}]")"
expect "$RC" 0 "CHANGES_REQUESTED at head => REVIEWED"

# 8. The two shapes the review loop is now required to emit, both accepted.
run "$(mkfix files-section "$HEAD" "[{\"state\":\"APPROVED\",\"commit_id\":\"$HEAD\",\"body\":\"$FILES_BODY\"}]")"
expect "$RC" 0 "### Files lines + 'No findings after checking' => REVIEWED"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
