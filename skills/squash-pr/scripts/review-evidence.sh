#!/usr/bin/env bash
# review-evidence.sh — does this PR carry a REAL review at its CURRENT head SHA?
#
# The autonomous merge gate's review leg used to be prose ("CodeRabbit's green check is not a
# review — read the bodies"). Prose is what an agent skips under load. This is the executable
# form: positive evidence or no merge.
#
# POSITIVE EVIDENCE, not absence of complaint. A green check means a bot RAN, not that it
# produced a verdict. CodeRabbit reports a passing check for at least three non-reviews:
# rate limit ("Review limit reached"), base-branch skip ("Auto reviews are disabled"), and
# free-plan-no-seat (walkthrough only, explicitly no line-by-line review). None of them leave
# a review body, so a body-based check needs no signature list to reject them — it simply
# finds nothing. The signatures are still matched, but only to report WHY, never to decide.
#
# AT THE CURRENT HEAD. A review of an older commit is evidence about code that is no longer
# the code being merged. Reviews carry `commit_id`; anything that does not match headRefOid
# is reported as stale and does not count.
#
# AND CARRYING EVIDENCE, not merely length. A body-length floor is a proxy, and a template
# defeats a proxy. On 2026-09-01 a review loop posted the same 126-character body on four PRs
# inside three seconds -- `Verdict: APPROVE`, every section reading `None`, no file named, no
# line cited -- and this guard passed all four, because 126 > 40. The floor is now 200 chars,
# and a body that is nothing but section labels reading `None`/`none` is rejected by shape
# regardless of its length: `UNREVIEWED: template-only review body`. A review that names no
# file and cites no line is the shape of a review, not a review.
#
# EXIT CODES — 3 is not a pass:
#   0  REVIEWED      at least one substantive review body at the current head SHA
#   1  UNREVIEWED    no such body (this is a definite answer: refuse the merge)
#   2  usage error
#   3  INDETERMINATE  could not tell — no gh, API error, malformed payload. The caller must
#                     treat this like 1 and refuse. A half-provisioned or offline machine is
#                     exactly when a check is most likely to be wrong, and collapsing 3 into 0
#                     rebuilds the defect the guard exists to prevent.
#
# Usage:
#   review-evidence.sh <pr-number> [--repo owner/name] [--min-body N] [--json]
#   REVIEW_EVIDENCE_FIXTURE_DIR=<dir> review-evidence.sh <pr-number>   # offline; see tests/
#
# Fixture dir contents (all optional; missing file = empty array):
#   reviews.json          gh api repos/{o}/{r}/pulls/{n}/reviews
#   issue_comments.json   gh api repos/{o}/{r}/issues/{n}/comments
#   head.txt              the PR's headRefOid
set -uo pipefail

MIN_BODY=200         # chars; shorter than this is "lgtm", not a review
PR=""; REPO=""; JSON=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)     REPO="${2:-}"; shift 2 ;;
    --min-body) MIN_BODY="${2:-}"; shift 2 ;;
    --json)     JSON=1; shift ;;
    -h|--help)  sed -n '2,43p' "$0"; exit 0 ;;
    -*)         echo "unknown flag: $1" >&2; exit 2 ;;
    *)          PR="$1"; shift ;;
  esac
done
[ -n "$PR" ] || { echo "usage: review-evidence.sh <pr-number> [--repo owner/name]" >&2; exit 2; }

FIX="${REVIEW_EVIDENCE_FIXTURE_DIR:-}"

emit() { # verdict reason
  if [ "$JSON" = 1 ]; then
    printf '{"verdict":"%s","reason":"%s","pr":"%s"}\n' "$1" "$2" "$PR"
  else
    printf '%s: %s\n' "$1" "$2"
  fi
}

if [ -n "$FIX" ]; then
  [ -d "$FIX" ] || { emit INDETERMINATE "fixture dir not found: $FIX"; exit 3; }
  read_json() { # file
    if [ -s "$FIX/$1" ]; then cat "$FIX/$1"; else echo '[]'; fi
  }
  REVIEWS="$(read_json reviews.json)"
  COMMENTS="$(read_json issue_comments.json)"
  HEAD="$(cat "$FIX/head.txt" 2>/dev/null || echo "")"
else
  command -v gh >/dev/null 2>&1 || { emit INDETERMINATE "gh not on PATH"; exit 3; }
  command -v jq >/dev/null 2>&1 || { emit INDETERMINATE "jq not on PATH"; exit 3; }
  R=(); [ -n "$REPO" ] && R=(--repo "$REPO")
  A=(); [ -n "$REPO" ] && A=(-H "Accept: application/vnd.github+json")
  OWNER_REPO="$REPO"
  if [ -z "$OWNER_REPO" ]; then
    OWNER_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" || {
      emit INDETERMINATE "cannot resolve repo (pass --repo owner/name)"; exit 3; }
  fi
  HEAD="$(gh pr view "$PR" "${R[@]}" --json headRefOid -q .headRefOid 2>/dev/null)" || HEAD=""
  [ -n "$HEAD" ] || { emit INDETERMINATE "cannot read headRefOid for #$PR"; exit 3; }
  REVIEWS="$(gh api "${A[@]}" "repos/$OWNER_REPO/pulls/$PR/reviews" 2>/dev/null)" || {
    emit INDETERMINATE "reviews API call failed for #$PR"; exit 3; }
  COMMENTS="$(gh api "${A[@]}" "repos/$OWNER_REPO/issues/$PR/comments" 2>/dev/null)" || COMMENTS='[]'
fi

# Malformed payloads are INDETERMINATE, never "no reviews found".
echo "$REVIEWS"  | jq -e 'type=="array"' >/dev/null 2>&1 || { emit INDETERMINATE "reviews payload is not an array"; exit 3; }
echo "$COMMENTS" | jq -e 'type=="array"' >/dev/null 2>&1 || COMMENTS='[]'
[ -n "$HEAD" ] || { emit INDETERMINATE "no head SHA available"; exit 3; }

# --- template detection -------------------------------------------------------------------
# A review body earns credit by naming something. `has_hard_evidence` is that test: a `### Files`
# section, a `path:line` citation, or the explicit "No findings after checking:" line the review
# loop emits when a clean PR really was read.
#
# `is_template_only` is the complement, and it is deliberately shape-based rather than a
# blocklist of known bodies. Drop the `## Review` heading, drop the `Verdict:` line, drop every
# section label whose value is empty or `None`. If nothing is left, the body said nothing. That
# catches a padded template as readily as the 126-char original, and it cannot be defeated by
# adding words to the heading.
# shellcheck disable=SC2016  # jq program text; $h and $n are jq params, not shell vars
JQ_DEFS='
def has_hard_evidence:
  test("(^|\n)[ \t]*#{2,6}[ \t]+Files\\b"; "i")
  or test("[A-Za-z0-9_][A-Za-z0-9_./-]*[./][A-Za-z0-9_-]+:[0-9]+")
  or test("No findings after checking"; "i");

def is_template_only:
  (has_hard_evidence | not)
  and test("Verdict[ \t]*:?[ \t]*\\**[ \t]*APPROVE"; "i")
  and ([ split("\n")[]
         | sub("^[ \t]+"; "") | sub("[ \t]+$"; "")
         | select(length > 0)
         | select(test("^([*_> \t]*#{1,6}[ \t]*Review\\b|\\*\\*Review\\b)"; "i") | not)
         | select(test("^[*_> \t]*Verdict[ \t]*:"; "i") | not)
         | select(test("^[*_`> \t-]*(HIGH|MEDIUM[ \t]*/?[ \t]*NIT|MEDIUM|NIT|LOW|CRITICAL|Not[ \t]+reviewed)[*_`]*[ \t]*[:—-]?[ \t]*\\**[ \t]*(none[.]?)?\\**[ \t]*$"; "i") | not)
         | select(test("^[*_`> \t-]*(none|n/a)[.]?[*_`]*$"; "i") | not)
       ] | length) == 0;

def submitted($h): select(.state != "PENDING") | select((.commit_id // "") == $h);
'

# Substantive review bodies at the current head: long enough AND not a bare template.
# CHANGES_REQUESTED counts as evidence a review happened — it blocks the merge elsewhere in
# the gate, not here.
AT_HEAD="$(echo "$REVIEWS" | jq --arg h "$HEAD" --argjson n "$MIN_BODY" "$JQ_DEFS"'
  [ .[] | submitted($h)
        | select((.body // "" | length) >= $n)
        | select((.body // "") | is_template_only | not) ] | length')"

# Bodies at head that were rejected only because they are templates. Reported as its own
# reason so the hook message names the cause instead of "no substantive review body".
TEMPLATE_AT_HEAD="$(echo "$REVIEWS" | jq --arg h "$HEAD" "$JQ_DEFS"'
  [ .[] | submitted($h)
        | select((.body // "") | is_template_only) ] | length')"

STALE="$(echo "$REVIEWS" | jq --arg h "$HEAD" --argjson n "$MIN_BODY" "$JQ_DEFS"'
  [ .[] | select((.body // "" | length) >= $n)
        | select(.state != "PENDING")
        | select((.body // "") | is_template_only | not)
        | select((.commit_id // "") != $h) ] | length')"

# Why CodeRabbit contributed nothing — reported, never decisive.
CR_NOTE=""
CR_BODY="$(echo "$COMMENTS" | jq -r '[.[] | select((.user.login // "") | test("coderabbit";"i")) | .body] | join("\n")')"
case "$CR_BODY" in
  *"Review limit reached"*|*"couldn't start this review"*) CR_NOTE=" (CodeRabbit: rate-limited)" ;;
  *"Auto reviews are disabled"*|*"Review skipped"*)        CR_NOTE=" (CodeRabbit: skipped)" ;;
  *"no line-by-line"*|*"free plan"*)                       CR_NOTE=" (CodeRabbit: no seat)" ;;
esac

if [ "$AT_HEAD" -gt 0 ] 2>/dev/null; then
  emit REVIEWED "$AT_HEAD substantive review body/bodies at head ${HEAD:0:8}$CR_NOTE"
  exit 0
fi

if [ "$TEMPLATE_AT_HEAD" -gt 0 ] 2>/dev/null; then
  emit UNREVIEWED "template-only review body — $TEMPLATE_AT_HEAD review(s) at head ${HEAD:0:8} name no file, cite no line, and read None/none throughout$CR_NOTE"
  exit 1
fi

if [ "$STALE" -gt 0 ] 2>/dev/null; then
  emit UNREVIEWED "$STALE review(s) exist but none at head ${HEAD:0:8} — code changed since$CR_NOTE"
  exit 1
fi

emit UNREVIEWED "no substantive review body (min ${MIN_BODY} chars, with a named file or cited line) on #$PR$CR_NOTE"
exit 1
