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

MIN_BODY=40          # chars; shorter than this is "lgtm", not a review
PR=""; REPO=""; JSON=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)     REPO="${2:-}"; shift 2 ;;
    --min-body) MIN_BODY="${2:-}"; shift 2 ;;
    --json)     JSON=1; shift ;;
    -h|--help)  sed -n '2,32p' "$0"; exit 0 ;;
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

# Substantive review bodies at the current head. CHANGES_REQUESTED counts as evidence a
# review happened — it blocks the merge elsewhere in the gate, not here.
AT_HEAD="$(echo "$REVIEWS" | jq --arg h "$HEAD" --argjson n "$MIN_BODY" '
  [ .[] | select((.body // "" | length) >= $n)
        | select(.state != "PENDING")
        | select((.commit_id // "") == $h) ] | length')"

STALE="$(echo "$REVIEWS" | jq --arg h "$HEAD" --argjson n "$MIN_BODY" '
  [ .[] | select((.body // "" | length) >= $n)
        | select(.state != "PENDING")
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

if [ "$STALE" -gt 0 ] 2>/dev/null; then
  emit UNREVIEWED "$STALE review(s) exist but none at head ${HEAD:0:8} — code changed since$CR_NOTE"
  exit 1
fi

emit UNREVIEWED "no substantive review body (min ${MIN_BODY} chars) on #$PR$CR_NOTE"
exit 1
