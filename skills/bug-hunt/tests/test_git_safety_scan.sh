#!/usr/bin/env bash
set -euo pipefail

# Tests for git_safety_scan.sh — the scanner that detects forbidden git ops
# in reflog after each bug-hunt iteration.
#
# Run:
#   bash skills/bug-hunt/tests/test_git_safety_scan.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER="${SCRIPT_DIR}/../scripts/git_safety_scan.sh"

if [[ ! -f "$HELPER" ]]; then
  echo "FAIL: helper not found at $HELPER"
  exit 1
fi

# shellcheck source=../scripts/git_safety_scan.sh
source "$HELPER"

PASS=0
FAIL=0

run_case() {
  local name="$1"
  shift
  echo ""
  echo "--- CASE: $name ---"
  if "$@"; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    FAIL=$((FAIL + 1))
  fi
}

# Fresh throwaway repo per case, so reflog state is isolated.
mk_repo() {
  local d
  d="$(mktemp -d -t bug-hunt-safety-test.XXXXXX)"
  (
    cd "$d"
    git init -q -b main
    git config user.email test@example.com
    git config user.name "Test User"
    echo a > a.txt
    git add a.txt
    git -c commit.gpgsign=false commit -q -m initial
    echo b > a.txt
    git add a.txt
    git -c commit.gpgsign=false commit -q -m second
  )
  echo "$d"
}

case_detects_amend() {
  local repo rc=0
  repo="$(mk_repo)"
  (
    cd "$repo"
    start=$(( $(date +%s) - 2 ))
    echo b-amended > a.txt
    git add a.txt
    git -c commit.gpgsign=false commit -q --amend --no-edit
    v=$(git_safety_scan_since "$start")
    if [[ -z "$v" ]]; then
      echo "    expected violation, got nothing"
      exit 1
    fi
    if ! grep -qE 'commit \(amend\)' <<<"$v"; then
      echo "    violation did not mention 'commit (amend)': $v"
      exit 1
    fi
  ) || rc=$?
  rm -rf "$repo"
  return $rc
}

case_detects_rebase() {
  local repo rc=0
  repo="$(mk_repo)"
  (
    cd "$repo"
    git checkout -q -b feature
    echo c > a.txt
    git add a.txt
    git -c commit.gpgsign=false commit -q -m third
    git checkout -q main
    echo d > b.txt
    git add b.txt
    git -c commit.gpgsign=false commit -q -m fourth
    start=$(( $(date +%s) - 2 ))
    git -c commit.gpgsign=false rebase -q feature || true
    v=$(git_safety_scan_since "$start")
    if ! grep -qE 'rebase' <<<"$v"; then
      echo "    expected rebase entry, got: $v"
      exit 1
    fi
  ) || rc=$?
  rm -rf "$repo"
  return $rc
}

case_detects_cherry_pick() {
  local repo rc=0
  repo="$(mk_repo)"
  (
    cd "$repo"
    git checkout -q -b feature
    echo c > c.txt
    git add c.txt
    git -c commit.gpgsign=false commit -q -m "feature change"
    target=$(git rev-parse HEAD)
    git checkout -q main
    start=$(( $(date +%s) - 2 ))
    git -c commit.gpgsign=false cherry-pick "$target" >/dev/null
    v=$(git_safety_scan_since "$start")
    if ! grep -qE 'cherry-pick' <<<"$v"; then
      echo "    expected cherry-pick entry, got: $v"
      exit 1
    fi
  ) || rc=$?
  rm -rf "$repo"
  return $rc
}

case_detects_reset() {
  local repo rc=0
  repo="$(mk_repo)"
  (
    cd "$repo"
    start=$(( $(date +%s) - 2 ))
    git reset -q --hard HEAD~1
    v=$(git_safety_scan_since "$start")
    if ! grep -qE 'reset' <<<"$v"; then
      echo "    expected reset entry, got: $v"
      exit 1
    fi
  ) || rc=$?
  rm -rf "$repo"
  return $rc
}

case_clean_iteration_no_false_positive() {
  local repo rc=0
  repo="$(mk_repo)"
  (
    cd "$repo"
    start=$(( $(date +%s) - 2 ))
    echo c > c.txt
    git add c.txt
    git -c commit.gpgsign=false commit -q -m "new commit (legal)"
    v=$(git_safety_scan_since "$start")
    if [[ -n "$v" ]]; then
      echo "    false positive on clean iteration: $v"
      exit 1
    fi
  ) || rc=$?
  rm -rf "$repo"
  return $rc
}

case_old_violation_outside_window_ignored() {
  local repo rc=0
  repo="$(mk_repo)"
  (
    cd "$repo"
    echo b-amended > a.txt
    git add a.txt
    git -c commit.gpgsign=false commit -q --amend --no-edit
    sleep 2
    start=$(date +%s)
    sleep 1
    echo c > c.txt
    git add c.txt
    git -c commit.gpgsign=false commit -q -m "new commit (legal)"
    v=$(git_safety_scan_since "$start")
    if [[ -n "$v" ]]; then
      echo "    violation outside window leaked into scan: $v"
      exit 1
    fi
  ) || rc=$?
  rm -rf "$repo"
  return $rc
}

# Cross-branch checkout — the engine moved HEAD off the dispatch branch.
case_detects_cross_branch_checkout() {
  local repo rc=0
  repo="$(mk_repo)"
  (
    cd "$repo"
    git checkout -q -b feature
    git checkout -q main
    start=$(( $(date +%s) - 2 ))
    git checkout -q feature
    v=$(git_safety_scan_since "$start")
    if ! grep -qE 'checkout: moving from' <<<"$v"; then
      echo "    expected checkout entry, got: $v"
      exit 1
    fi
  ) || rc=$?
  rm -rf "$repo"
  return $rc
}

# Same-branch checkout is a no-op and must NOT trigger a violation.
case_same_branch_checkout_not_detected() {
  local repo rc=0
  repo="$(mk_repo)"
  (
    cd "$repo"
    start=$(( $(date +%s) - 2 ))
    git checkout -q main
    v=$(git_safety_scan_since "$start")
    if [[ -n "$v" ]]; then
      echo "    false positive on same-branch checkout: $v"
      exit 1
    fi
  ) || rc=$?
  rm -rf "$repo"
  return $rc
}

# Filter exposed directly — pipe synthetic reflog text in to verify the
# regex + same-branch post-filter without needing a real git state.
case_filter_pull_entry() {
  v=$(printf '%s\n' 'abc1234 HEAD@{0}: pull: Fast-forward' | git_safety_filter_reflog)
  if ! grep -qE 'pull' <<<"$v"; then
    echo "    expected pull entry to pass filter, got: $v"
    return 1
  fi
}

case_filter_pull_ff_only() {
  v=$(printf '%s\n' 'abc1234 HEAD@{0}: pull --ff-only: Fast-forward' | git_safety_filter_reflog)
  if ! grep -qE 'pull' <<<"$v"; then
    echo "    expected pull --ff-only entry to pass filter, got: $v"
    return 1
  fi
}

case_filter_fetch_entry() {
  v=$(printf '%s\n' 'abc1234 HEAD@{0}: fetch: update' | git_safety_filter_reflog)
  if ! grep -qE 'fetch' <<<"$v"; then
    echo "    expected fetch entry to pass filter, got: $v"
    return 1
  fi
}

case_filter_same_branch_dropped() {
  v=$(printf '%s\n' 'abc1234 HEAD@{0}: checkout: moving from dev to dev' | git_safety_filter_reflog)
  if [[ -n "$v" ]]; then
    echo "    same-branch checkout should be filtered out, got: $v"
    return 1
  fi
}

case_filter_cross_branch_kept() {
  v=$(printf '%s\n' 'abc1234 HEAD@{0}: checkout: moving from dev to feature' | git_safety_filter_reflog)
  if [[ -z "$v" ]]; then
    echo "    cross-branch checkout should be kept, got nothing"
    return 1
  fi
}

# Commit message that happens to contain the word "pull" must NOT trip the
# scanner — the pattern is anchored to ': pull[ :]' so an arbitrary commit
# subject is safe.
case_filter_pull_in_commit_subject_safe() {
  v=$(printf '%s\n' 'abc1234 HEAD@{0}: commit: refactor pull-request flow' | git_safety_filter_reflog)
  if [[ -n "$v" ]]; then
    echo "    'pull' inside a commit subject should not match, got: $v"
    return 1
  fi
}

# HEAD-branch assertion: scanner called with start_branch=A while HEAD is on
# B flags drift, independent of any reflog entry.
case_head_branch_drift_flagged() {
  local repo rc=0
  repo="$(mk_repo)"
  (
    cd "$repo"
    git checkout -q -b feature
    start=$(( $(date +%s) - 2 ))
    # Simulate the orchestrator passing a stale start_branch.
    v=$(git_safety_scan_since "$start" "main")
    if ! grep -qE 'HEAD-BRANCH-DRIFT' <<<"$v"; then
      echo "    expected HEAD-BRANCH-DRIFT, got: $v"
      exit 1
    fi
    if ! grep -qE 'started on main, now on feature' <<<"$v"; then
      echo "    drift line missing from/to detail: $v"
      exit 1
    fi
  ) || rc=$?
  rm -rf "$repo"
  return $rc
}

case_head_branch_match_clean() {
  local repo rc=0
  repo="$(mk_repo)"
  (
    cd "$repo"
    start=$(( $(date +%s) - 2 ))
    echo c > c.txt
    git add c.txt
    git -c commit.gpgsign=false commit -q -m "new commit (legal)"
    v=$(git_safety_scan_since "$start" "main")
    if [[ -n "$v" ]]; then
      echo "    expected clean scan with matching branch, got: $v"
      exit 1
    fi
  ) || rc=$?
  rm -rf "$repo"
  return $rc
}

run_case "detects commit --amend"                  case_detects_amend
run_case "detects rebase"                          case_detects_rebase
run_case "detects cherry-pick"                     case_detects_cherry_pick
run_case "detects reset"                           case_detects_reset
run_case "clean iteration has no false positive"   case_clean_iteration_no_false_positive
run_case "old violation outside window ignored"    case_old_violation_outside_window_ignored
run_case "detects cross-branch checkout"           case_detects_cross_branch_checkout
run_case "same-branch checkout not detected"       case_same_branch_checkout_not_detected
run_case "filter: pull reflog entry detected"      case_filter_pull_entry
run_case "filter: pull --ff-only detected"         case_filter_pull_ff_only
run_case "filter: fetch reflog entry detected"     case_filter_fetch_entry
run_case "filter: same-branch checkout dropped"    case_filter_same_branch_dropped
run_case "filter: cross-branch checkout kept"      case_filter_cross_branch_kept
run_case "filter: 'pull' in commit subject safe"   case_filter_pull_in_commit_subject_safe
run_case "HEAD-branch drift flagged"               case_head_branch_drift_flagged
run_case "HEAD-branch match yields clean scan"     case_head_branch_match_clean

echo ""
echo "=== RESULT: ${PASS} passed, ${FAIL} failed ==="
[[ $FAIL -eq 0 ]]
