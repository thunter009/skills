#!/usr/bin/env bash
set -uo pipefail

# Tests for exclude_enforce.sh — orchestrator-side enforcement of
# --exclude-files. Engines have ignored the prompt-level "DO NOT MODIFY"
# notice before; this layer detects post-hoc commits that touched excluded
# paths and remediates them.
#
# Run:
#   bash skills/bug-hunt/tests/test_exclude_files_enforcement.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER="${SCRIPT_DIR}/../scripts/exclude_enforce.sh"

if [[ ! -f "$HELPER" ]]; then
  echo "FAIL: helper not found at $HELPER"
  exit 1
fi

# shellcheck source=../scripts/exclude_enforce.sh
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

# Throwaway repo with an initial commit + a configured user. Caller can add
# commits past start_sha to simulate engine activity.
mk_repo() {
  local d
  d="$(mktemp -d -t bug-hunt-exclude-test.XXXXXX)"
  (
    cd "$d" || exit 1
    git init -q -b main
    git config user.email test@example.com
    git config user.name "Test User"
    mkdir -p protected src
    echo "original-protected" > protected/secret.txt
    echo "original-src" > src/normal.txt
    git add protected/secret.txt src/normal.txt
    git -c commit.gpgsign=false commit -q -m "initial"
  )
  echo "$d"
}

# Case (a): engine commit touches ONLY excluded files → whole-commit revert.
case_whole_commit_revert() {
  local repo rc=0
  repo="$(mk_repo)"
  (
    cd "$repo"
    start_sha=$(git rev-parse HEAD)
    echo "engine-tampered" > protected/secret.txt
    git add protected/secret.txt
    git -c commit.gpgsign=false commit -q -m "engine touched only protected"
    bad_sha=$(git rev-parse HEAD)

    exclude_file=$(mktemp)
    echo "protected/secret.txt" > "$exclude_file"

    output=$(bug_hunt_exclude_enforce "$start_sha" "$exclude_file" 2>&1)
    rm -f "$exclude_file"

    if ! grep -qE '!!! EXCLUDE-FILE VIOLATION REMEDIATED !!!' <<<"$output"; then
      echo "    banner missing from output: $output"
      exit 1
    fi
    if ! grep -qE "Reverting commit ${bad_sha} \(all files excluded\)" <<<"$output"; then
      echo "    expected 'Reverting commit ${bad_sha} (all files excluded)', got: $output"
      exit 1
    fi
    # File contents restored to start_sha state
    if [[ "$(cat protected/secret.txt)" != "original-protected" ]]; then
      echo "    protected/secret.txt was not restored: $(cat protected/secret.txt)"
      exit 1
    fi
    # bad_sha still exists, but a revert commit sits on top
    if ! git rev-parse "$bad_sha" >/dev/null 2>&1; then
      echo "    bad commit ${bad_sha} should still exist in history"
      exit 1
    fi
    # HEAD is one commit ahead of bad_sha (the revert commit)
    if [[ "$(git rev-list --count "${bad_sha}..HEAD")" != "1" ]]; then
      echo "    expected exactly 1 revert commit on top of bad_sha"
      exit 1
    fi
  ) || rc=$?
  rm -rf "$repo"
  return $rc
}

# Case (b): engine commit mixes excluded + legitimate files → surgical
# restore. Legitimate changes survive; excluded paths revert to start_sha.
case_surgical_restore_mixed() {
  local repo rc=0
  repo="$(mk_repo)"
  (
    cd "$repo"
    start_sha=$(git rev-parse HEAD)
    echo "engine-tampered"   > protected/secret.txt
    echo "legit-fix"         > src/normal.txt
    git add protected/secret.txt src/normal.txt
    git -c commit.gpgsign=false commit -q -m "mixed: legit fix + protected touch"
    mixed_sha=$(git rev-parse HEAD)

    exclude_file=$(mktemp)
    echo "protected/secret.txt" > "$exclude_file"

    output=$(bug_hunt_exclude_enforce "$start_sha" "$exclude_file" 2>&1)
    rm -f "$exclude_file"

    if ! grep -qE '!!! EXCLUDE-FILE VIOLATION REMEDIATED !!!' <<<"$output"; then
      echo "    banner missing: $output"
      exit 1
    fi
    if ! grep -qE "Surgical restore from ${mixed_sha}" <<<"$output"; then
      echo "    expected 'Surgical restore from ${mixed_sha}', got: $output"
      exit 1
    fi
    # Excluded path restored to start_sha state
    if [[ "$(cat protected/secret.txt)" != "original-protected" ]]; then
      echo "    excluded path not restored: $(cat protected/secret.txt)"
      exit 1
    fi
    # Legitimate change preserved
    if [[ "$(cat src/normal.txt)" != "legit-fix" ]]; then
      echo "    legitimate change wiped: $(cat src/normal.txt)"
      exit 1
    fi
    # No `git revert` should have happened for this commit (mixed → surgical only)
    if grep -qE "Reverting commit ${mixed_sha}" <<<"$output"; then
      echo "    mixed commit should NOT be whole-revert: $output"
      exit 1
    fi
    # Exactly one new commit on top (the surgical-restore commit)
    if [[ "$(git rev-list --count "${mixed_sha}..HEAD")" != "1" ]]; then
      echo "    expected exactly 1 surgical-restore commit on top"
      exit 1
    fi
  ) || rc=$?
  rm -rf "$repo"
  return $rc
}

# Case (c): engine commit touches NO excluded files → no remediation, no
# banner, no extra commits.
case_no_remediation_when_clean() {
  local repo rc=0
  repo="$(mk_repo)"
  (
    cd "$repo"
    start_sha=$(git rev-parse HEAD)
    echo "legit-fix" > src/normal.txt
    git add src/normal.txt
    git -c commit.gpgsign=false commit -q -m "legitimate fix only"
    clean_sha=$(git rev-parse HEAD)

    exclude_file=$(mktemp)
    echo "protected/secret.txt" > "$exclude_file"

    output=$(bug_hunt_exclude_enforce "$start_sha" "$exclude_file" 2>&1)
    rm -f "$exclude_file"

    if [[ -n "$output" ]]; then
      echo "    expected silent no-op, got: $output"
      exit 1
    fi
    # No commit added on top of clean_sha
    if [[ "$(git rev-parse HEAD)" != "$clean_sha" ]]; then
      echo "    HEAD moved past clean_sha — unexpected remediation"
      exit 1
    fi
  ) || rc=$?
  rm -rf "$repo"
  return $rc
}

# Engine creates a NEW excluded file that didn't exist at start_sha →
# remediation should remove it (since there's nothing to "restore back to").
case_engine_creates_excluded_file() {
  local repo rc=0
  repo="$(mk_repo)"
  (
    cd "$repo"
    start_sha=$(git rev-parse HEAD)
    mkdir -p protected
    echo "new-secret" > protected/leak.txt
    echo "legit-fix"  > src/normal.txt
    git add protected/leak.txt src/normal.txt
    git -c commit.gpgsign=false commit -q -m "mixed: legit + new protected file"

    exclude_file=$(mktemp)
    # Use glob to verify glob-matching works in the helper
    echo "protected/*" > "$exclude_file"

    output=$(bug_hunt_exclude_enforce "$start_sha" "$exclude_file" 2>&1)
    rm -f "$exclude_file"

    if ! grep -qE '!!! EXCLUDE-FILE VIOLATION REMEDIATED !!!' <<<"$output"; then
      echo "    banner missing: $output"
      exit 1
    fi
    if [[ -f protected/leak.txt ]]; then
      echo "    new excluded file should have been removed"
      exit 1
    fi
    # Legitimate file preserved
    if [[ "$(cat src/normal.txt)" != "legit-fix" ]]; then
      echo "    legitimate change wiped: $(cat src/normal.txt)"
      exit 1
    fi
  ) || rc=$?
  rm -rf "$repo"
  return $rc
}

# A mixed commit may touch an excluded file that a later commit has already
# restored to start_sha. That no-op surgical restore must not leave a stale
# restore queue that prevents a subsequent all-excluded commit from reverting.
case_noop_surgical_restore_does_not_skip_later_revert() {
  local repo rc=0
  repo="$(mk_repo)"
  (
    cd "$repo"
    start_sha=$(git rev-parse HEAD)
    echo "original-other" > protected/other.txt
    git add protected/other.txt
    git -c commit.gpgsign=false commit -q -m "add second protected file"
    start_sha=$(git rev-parse HEAD)

    echo "engine-tampered" > protected/secret.txt
    echo "legit-1" > src/normal.txt
    git add protected/secret.txt src/normal.txt
    git -c commit.gpgsign=false commit -q -m "mixed: protected touch"

    echo "original-protected" > protected/secret.txt
    echo "legit-2" > src/normal.txt
    git add protected/secret.txt src/normal.txt
    git -c commit.gpgsign=false commit -q -m "mixed: self-restore protected"

    echo "other-tampered" > protected/other.txt
    git add protected/other.txt
    git -c commit.gpgsign=false commit -q -m "protected-only later"
    protected_only_sha=$(git rev-parse HEAD)

    exclude_file=$(mktemp)
    echo "protected/*" > "$exclude_file"

    output=$(bug_hunt_exclude_enforce "$start_sha" "$exclude_file" 2>&1)
    rm -f "$exclude_file"

    if grep -qE "surgical-restore commit failed before revert" <<<"$output"; then
      echo "    stale no-op restore queue blocked the later revert: $output"
      exit 1
    fi
    if ! grep -qE "Reverting commit ${protected_only_sha} \(all files excluded\)" <<<"$output"; then
      echo "    expected later all-excluded commit to be reverted, got: $output"
      exit 1
    fi
    if [[ "$(cat protected/secret.txt)" != "original-protected" ]]; then
      echo "    secret was not left restored: $(cat protected/secret.txt)"
      exit 1
    fi
    if [[ "$(cat protected/other.txt)" != "original-other" ]]; then
      echo "    later all-excluded commit was not reverted: $(cat protected/other.txt)"
      exit 1
    fi
    if [[ "$(cat src/normal.txt)" != "legit-2" ]]; then
      echo "    legitimate change was lost: $(cat src/normal.txt)"
      exit 1
    fi
  ) || rc=$?
  rm -rf "$repo"
  return $rc
}

# Engine made no commits since start_sha → no remediation, silent.
case_no_commits_since_start() {
  local repo rc=0
  repo="$(mk_repo)"
  (
    cd "$repo"
    start_sha=$(git rev-parse HEAD)
    exclude_file=$(mktemp)
    echo "protected/secret.txt" > "$exclude_file"
    output=$(bug_hunt_exclude_enforce "$start_sha" "$exclude_file" 2>&1)
    rm -f "$exclude_file"
    if [[ -n "$output" ]]; then
      echo "    expected silent no-op when no commits, got: $output"
      exit 1
    fi
  ) || rc=$?
  rm -rf "$repo"
  return $rc
}

# Empty exclude list → silent no-op even with engine commits.
case_empty_exclude_list_silent() {
  local repo rc=0
  repo="$(mk_repo)"
  (
    cd "$repo"
    start_sha=$(git rev-parse HEAD)
    echo "engine-tampered" > protected/secret.txt
    git add protected/secret.txt
    git -c commit.gpgsign=false commit -q -m "would-be violation"
    bad_sha=$(git rev-parse HEAD)

    exclude_file=$(mktemp)
    # Empty file
    output=$(bug_hunt_exclude_enforce "$start_sha" "$exclude_file" 2>&1)
    rm -f "$exclude_file"

    if [[ -n "$output" ]]; then
      echo "    expected silent no-op on empty list, got: $output"
      exit 1
    fi
    if [[ "$(git rev-parse HEAD)" != "$bad_sha" ]]; then
      echo "    HEAD moved despite empty exclude list"
      exit 1
    fi
  ) || rc=$?
  rm -rf "$repo"
  return $rc
}

run_case "whole-commit revert when only excluded files"  case_whole_commit_revert
run_case "surgical restore preserves legitimate work"    case_surgical_restore_mixed
run_case "no remediation when no excluded files touched" case_no_remediation_when_clean
run_case "new excluded file removed by remediation"      case_engine_creates_excluded_file
run_case "no-op surgical restore does not skip later revert" case_noop_surgical_restore_does_not_skip_later_revert
run_case "silent when no commits since start_sha"        case_no_commits_since_start
run_case "silent when exclude list is empty"             case_empty_exclude_list_silent

echo ""
echo "=== RESULT: ${PASS} passed, ${FAIL} failed ==="
[[ $FAIL -eq 0 ]]
