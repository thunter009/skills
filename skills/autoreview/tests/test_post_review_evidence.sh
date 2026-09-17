#!/usr/bin/env bash
# Tests for post-review-evidence.sh — hermetic, no gh. The composed body is fed straight into
# squash-pr's review-evidence.sh through its fixture dir, so the test asserts the one thing
# that matters: the merge gate counts what this script posts.
# shellcheck disable=SC2016  # backticks inside single-quoted patterns are markdown, not command substitution
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POST="$HERE/../scripts/post-review-evidence.sh"
GUARD="$HERE/../../squash-pr/scripts/review-evidence.sh"
[ -f "$GUARD" ] || { echo "skip: $GUARD missing"; exit 0; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/post-review-evidence-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1" >&2; }
expect() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

HEAD=99d43c88aa11bb22cc33dd44ee55ff6677889900
gate() { # body-file -> RC, OUT   (review at HEAD, state COMMENTED)
  local d="$TMP/fix.$RANDOM"; mkdir -p "$d"
  printf '%s' "$HEAD" > "$d/head.txt"
  jq -n --arg h "$HEAD" --rawfile b "$1" '[{"state":"COMMENTED","commit_id":$h,"body":$b,"user":{"login":"thunter009"}}]' > "$d/reviews.json"
  OUT="$(REVIEW_EVIDENCE_FIXTURE_DIR="$d" bash "$GUARD" 999 2>&1)"; RC=$?
}

# 1. clean run → body names files, gate says REVIEWED
printf '{"findings":[],"overall_correctness":"patch is correct","overall_explanation":"No actionable defects.","overall_confidence":0.83}' > "$TMP/clean.json"
bash "$POST" 999 --from "$TMP/clean.json" --dry-run --head "$HEAD" --files "scripts/a.py,tests/test_a.py" --rounds 3 > "$TMP/clean.md"; expect "$?" 0 "clean: dry-run exits 0"
case "$(cat "$TMP/clean.md")" in *"### Files"*"scripts/a.py"*"No findings after checking:** scripts/a.py, tests/test_a.py"*) ok "clean: names files + 'No findings after checking'" ;; *) bad "clean body shape: $(cat "$TMP/clean.md")" ;; esac
case "$(cat "$TMP/clean.md")" in *"Verdict: APPROVE"*) ok "clean: verdict APPROVE" ;; *) bad "clean verdict" ;; esac
gate "$TMP/clean.md"; expect "$RC" 0 "clean: review-evidence.sh => REVIEWED ($OUT)"

# 2. findings open → cites path:line, verdict not APPROVE, still counts as evidence
printf '{"findings":[{"title":"Export collides","priority":"P1","code_location":{"file_path":"scripts/a.py","line":320}}],"overall_correctness":"patch is incorrect","overall_explanation":"one defect"}' > "$TMP/open.json"
bash "$POST" 999 --from "$TMP/open.json" --dry-run --head "$HEAD" --files "scripts/a.py" > "$TMP/open.md"; expect "$?" 0 "open: dry-run exits 0"
case "$(cat "$TMP/open.md")" in *'`scripts/a.py:320`'*"CHANGES REQUESTED"*|*"CHANGES REQUESTED"*'`scripts/a.py:320`'*) ok "open: cites path:line, verdict CHANGES REQUESTED" ;; *) bad "open body: $(cat "$TMP/open.md")" ;; esac
gate "$TMP/open.md"; expect "$RC" 0 "open: gate still sees a review body at head"

# 3. refusals
bash "$POST" 999 --from "$TMP/missing.json" --dry-run --head "$HEAD" --files a >/dev/null 2>&1; expect "$?" 1 "refuse: missing json"
printf 'not json' > "$TMP/bad.json"; bash "$POST" 999 --from "$TMP/bad.json" --dry-run --head "$HEAD" --files a >/dev/null 2>&1; expect "$?" 1 "refuse: malformed json"
# hermetic "gh is broken/absent": a stub gh that always fails shadows the real one
mkdir -p "$TMP/nogh"; printf '#!/bin/sh\necho "stub gh: refusing" >&2; exit 1\n' > "$TMP/nogh/gh"; chmod +x "$TMP/nogh/gh"
PATH="$TMP/nogh:$PATH" bash "$POST" 999 --from "$TMP/clean.json" --dry-run --head "$HEAD" --files "" >/dev/null 2>&1; expect "$?" 1 "refuse: empty --files and gh unusable"
bash "$POST" 999 --from "$TMP/clean.json" --dry-run --head "$HEAD" --files >/dev/null 2>&1; expect "$?" 2 "refuse: trailing flag with no value is a usage error, not a hang"
bash "$POST" --from "$TMP/clean.json" --dry-run >/dev/null 2>&1; expect "$?" 2 "refuse: no PR number"

# 4. a stale head in the gate fixture is NOT evidence (the poster pins commit_id; prove the gate cares)
d="$TMP/stale"; mkdir -p "$d"; printf '%s' "$HEAD" > "$d/head.txt"
jq -n --rawfile b "$TMP/clean.md" '[{"state":"COMMENTED","commit_id":"0000000000000000000000000000000000000000","body":$b,"user":{"login":"x"}}]' > "$d/reviews.json"
OUT="$(REVIEW_EVIDENCE_FIXTURE_DIR="$d" bash "$GUARD" 999 2>&1)"; expect "$?" 1 "stale head => UNREVIEWED ($OUT)"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ]
