#!/usr/bin/env bash
# check-dirty-beads.sh — exit-time guard against stranded bead closes (bd-1x5s).
#
# Two ways a `br close` never reaches origin, both observed 3+ times:
#   A. closes committed onto a local integration branch that had diverged from
#      its upstream; the commit never left the machine (2026-07-08/09).
#   B. closes never committed at all — the dirty `.beads/issues.jsonl` sat
#      unnoticed in `git status` while closeout attention went to another
#      repo (2026-08-05, agent-skills).
#
# This check covers both, and is repo-agnostic so a session that touched
# several repos can pass every one of them in a single call.
#
# Usage:
#   check-dirty-beads.sh [REPO_PATH ...]
#
# With no arguments, checks the current git repo.
#
# Exit codes:
#   0  every checked repo is clean (or skipped)
#   1  at least one repo has uncommitted .beads/ changes, has diverged, or
#      could not be verified because a git command failed
#   2  usage error
#
# A guard that cannot check must never report clean. Every git invocation
# below is checked by exit status, not by whether its output was empty — an
# empty result from a failed command is silence, not evidence.
set -uo pipefail

usage() {
  cat <<'USAGE'
Usage: check-dirty-beads.sh [REPO_PATH ...]

Reports, for every repo given (default: the current repo):
  - uncommitted changes under .beads/          (close never committed)
  - ahead/behind counts vs the upstream branch (close never pushed)

Paths that are not git repos, and repos without a .beads/ directory, are
skipped rather than treated as failures.

Exit 0 when everything is clean, 1 when anything is dirty, diverged, or
unverifiable (a git command failed), 2 on a usage error.
USAGE
}

REPOS=()
while (($# > 0)); do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      while (($# > 0)); do
        REPOS+=("$1")
        shift
      done
      ;;
    -*)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      REPOS+=("$1")
      shift
      ;;
  esac
done

if ((${#REPOS[@]} == 0)); then
  REPOS=(".")
fi

# Resolve the ref this branch should be compared against. Prefer the branch's
# own upstream (`@{u}`) — that is the ref a push would actually update. Only
# fall back to origin/<integration> when HEAD is itself an integration branch
# with no upstream configured; a feature branch with no upstream is compared
# against nothing, because "ahead of origin/dev" is its normal state.
#
# Returns: 0 = resolved (name on stdout)
#          1 = no upstream configured, nothing to compare (benign)
#          2 = an upstream IS configured but does not resolve locally, so
#              divergence is unverifiable (name on stdout, best effort)
resolve_upstream() {
  local top="$1" upstream branch candidate remote merge

  if upstream="$(git -C "$top" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" &&
    [[ -n "$upstream" ]]; then
    printf '%s\n' "$upstream"
    return 0
  fi

  branch="$(git -C "$top" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')"
  case "$branch" in
    dev | main | master)
      candidate="origin/$branch"
      if git -C "$top" rev-parse --verify --quiet "refs/remotes/$candidate" >/dev/null 2>&1; then
        printf '%s\n' "$candidate"
        return 0
      fi
      ;;
  esac

  # `@{u}` did not resolve. If the branch nonetheless declares an upstream, the
  # remote-tracking ref is missing (never fetched, or pruned) — that is an
  # unverifiable state, not a clean one.
  if [[ -n "$branch" ]]; then
    remote="$(git -C "$top" config --get "branch.$branch.remote" 2>/dev/null || printf '')"
    if [[ -n "$remote" ]]; then
      merge="$(git -C "$top" config --get "branch.$branch.merge" 2>/dev/null || printf '')"
      printf '%s/%s\n' "$remote" "${merge##refs/heads/}"
      return 2
    fi
  fi

  return 1
}

report() {
  printf "  %-8s %s\n" "$1" "$2"
}

# Echo an indented copy of a captured git error, for the ERROR paths.
report_detail() {
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && printf "            %s\n" "$line"
  done <<<"$1"
}

FAILED=0
CHECKED=0

for repo in "${REPOS[@]}"; do
  if [[ ! -d "$repo" ]]; then
    report "skip" "$repo — path does not exist"
    continue
  fi

  if ! top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || [[ -z "$top" ]]; then
    report "skip" "$repo — not a git repo"
    continue
  fi

  if [[ ! -d "$top/.beads" ]]; then
    report "skip" "$top — no .beads/ directory"
    continue
  fi

  CHECKED=$((CHECKED + 1))
  repo_failed=0

  # Exit status, not empty output, decides. `git status` failing (corrupt
  # index, unreadable object store, lock contention) must not read as "no
  # dirty files" — that is a guard reporting success without checking.
  dirty_status=0
  dirty="$(git -C "$top" status --porcelain -- .beads/ 2>/dev/null)" || dirty_status=$?
  if ((dirty_status != 0)); then
    report "ERROR" "$top — git status failed (exit $dirty_status); bead state NOT verified"
    report_detail "$(git -C "$top" status --porcelain -- .beads/ 2>&1 >/dev/null)"
    repo_failed=1
  elif [[ -n "$dirty" ]]; then
    dirty_count="$(printf '%s\n' "$dirty" | grep -c .)"
    report "DIRTY" "$top — $dirty_count uncommitted change(s) under .beads/"
    report_detail "$dirty"
    repo_failed=1
  fi

  upstream_status=0
  upstream="$(resolve_upstream "$top")" || upstream_status=$?
  case "$upstream_status" in
    0)
      counts_status=0
      counts="$(git -C "$top" rev-list --left-right --count "HEAD...$upstream" 2>/dev/null)" ||
        counts_status=$?
      if ((counts_status != 0)); then
        report "ERROR" "$top — cannot compare HEAD against $upstream (git rev-list exit $counts_status); divergence NOT verified"
        repo_failed=1
      else
        ahead="${counts%%[[:space:]]*}"
        behind="${counts##*[[:space:]]}"
        if [[ "$ahead" != "0" || "$behind" != "0" ]]; then
          report "DIVERGED" "$top — HEAD is $ahead ahead / $behind behind $upstream"
          repo_failed=1
        fi
      fi
      ;;
    2)
      report "ERROR" "$top — upstream $upstream is configured but missing locally (run git fetch); divergence NOT verified"
      repo_failed=1
      ;;
    *)
      report "skip" "$top — no upstream branch to compare against"
      ;;
  esac

  if ((repo_failed == 0)); then
    report "clean" "$top"
  else
    FAILED=$((FAILED + 1))
  fi
done

if ((FAILED == 0)); then
  printf "check-dirty-beads: %d repo(s) checked, all clean\n" "$CHECKED"
  exit 0
fi

printf "check-dirty-beads: %d of %d repo(s) have unlanded or unverified bead state\n" \
  "$FAILED" "$CHECKED"
cat <<'REMEDIATION'
Remediation — never br-close and commit onto a stale local ref. Close in a
fresh worktree cut from the integration branch:
  git worktree add .ntm/worktrees/close-beads -b chore/close-beads origin/dev
  cd .ntm/worktrees/close-beads
  br close <ids> && br sync --flush-only
  git diff -- .beads/            # verify ONLY the intended beads changed
  git add .beads/ && git commit -m 'chore(beads): close <ids>'
  git push -u origin chore/close-beads && gh pr create --base dev   # then merge

An ERROR line means the check could not run at all. Fix the reported git
failure and re-run — an unverified repo is not a clean one.
REMEDIATION
exit 1
