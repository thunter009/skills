#!/usr/bin/env bash
# Shared helper: scan HEAD reflog for forbidden git ops since a given epoch,
# plus assert HEAD has not drifted off the iteration's start branch.
#
# Safe to source — declares only functions, no side effects. Do not set -e
# here; callers set their own shell flags.
#
# Usage:
#   iteration_start_epoch=$(date +%s)
#   iteration_start_branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
#   # ... run engine ...
#   violations=$(git_safety_scan_since "$iteration_start_epoch" "$iteration_start_branch")
#   [[ -n "$violations" ]] && echo "VIOLATION: $violations"
#
# Prints matching reflog lines plus any HEAD-branch drift line to stdout.
# Never exits non-zero.

# Patterns that identify forbidden operations in reflog subject lines.
# - "rebase"                → git rebase (pick/finish/squash/...)
# - "cherry-pick"           → git cherry-pick
# - "commit \(amend\)"      → git commit --amend
# - "reset"                 → git reset (hard/soft/mixed)
# - "revert"                → git revert (engine is banned even from forward-only revert)
# - "checkout: moving from" → git checkout / git switch. Same-branch checkouts
#                             (X == Y) are dropped by git_safety_filter_reflog.
# - ": pull[ :]"            → git pull (any form, including --ff-only / --rebase)
# - ": fetch[ :]"           → git fetch (any form). Note: bare `git fetch`
#                             typically doesn't write to HEAD reflog; this
#                             pattern catches the rare cases that do.
GIT_SAFETY_FORBIDDEN_RE='rebase|cherry-pick|commit \(amend\)|reset|revert|checkout: moving from|: pull[ :]|: fetch[ :]'

# Filter reflog lines on stdin: keep only forbidden-op entries, drop benign
# same-branch checkouts (engines occasionally emit `checkout: moving from X
# to X` as a no-op which is harmless and must not trigger a violation).
# Exposed for testability — callers can pipe synthetic reflog text in to
# verify the regex + post-filter without touching real git state.
git_safety_filter_reflog() {
  # grep does the regex match (passing the pattern through awk -v mangles
  # backslash escapes like \( \) in some awk implementations). awk then
  # drops benign same-branch checkout entries.
  { grep -E "$GIT_SAFETY_FORBIDDEN_RE" || true; } \
    | awk '
      {
        if (match($0, /checkout: moving from /)) {
          rest = substr($0, RSTART + RLENGTH)
          p = index(rest, " to ")
          if (p > 0) {
            from = substr(rest, 1, p - 1)
            aft = substr(rest, p + 4)
            n = split(aft, w, /[ \t]/)
            if (n > 0 && from == w[1]) next
          }
        }
        print
      }
    '
}

git_safety_scan_since() {
  local since_epoch="${1:?git_safety_scan_since: missing epoch arg}"
  local start_branch="${2:-}"
  local now_epoch elapsed
  now_epoch=$(date +%s)
  elapsed=$(( now_epoch - since_epoch ))
  # Clamp to >=1s so a sub-second iteration still yields a valid --since
  # window (git rejects "0 seconds ago" on some versions).
  (( elapsed < 1 )) && elapsed=1

  { git reflog --date=iso --since="${elapsed} seconds ago" 2>/dev/null || true; } \
    | git_safety_filter_reflog

  # HEAD-branch assertion: if a start_branch was passed, current HEAD must
  # still be on it. Detached HEAD or a different branch is a Layer-2
  # violation regardless of reflog content — the engine may have moved HEAD
  # via an op that left no forbidden reflog subject (or the reflog window
  # is too narrow to catch it).
  if [[ -n "$start_branch" ]]; then
    local current_branch
    current_branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "DETACHED")
    if [[ "$current_branch" != "$start_branch" ]]; then
      printf 'HEAD-BRANCH-DRIFT: started on %s, now on %s\n' \
        "$start_branch" "$current_branch"
    fi
  fi
}
