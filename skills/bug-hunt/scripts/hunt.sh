#!/usr/bin/env bash
set -euo pipefail

# bug-hunt: single-iteration engine-driven bug hunting with journal context
#
# Called by Claude Code in a loop. Each invocation runs ONE engine iteration.
# Claude Code handles the accumulation loop, Agent Mail posting, and journal
# injection between calls.
#
# Usage:
#   hunt.sh --phase <1|2|3> [--engine E] [--model M] [--journal-file PATH] [--exclude-files FILE] [--dry-run] [project_dir]
#
# Full standalone mode (all phases, all iterations — no journal accumulation):
#   hunt.sh --standalone [--engine E] [--iterations N] [--model M] [--dry-run] [project_dir]

MODE="single"
PHASE=""
ITERATIONS=3
ENGINE="codex"
MODEL=""
DRY_RUN=false
PROJECT_DIR=""
JOURNAL_FILE=""
EXCLUDE_FILE=""
MAX_PROMPT_KB=8  # cap total prompt at 8KB to avoid engine OOM
MAX_CONCURRENT="${SWARM_MAX_CONCURRENT:-2}"

require_value() {
  local flag="$1"
  local value="${2:-}"
  if [[ -z "$value" || "$value" == -* ]]; then
    printf 'ERROR: %s requires a value\n' "$flag" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)          require_value "$1" "${2:-}"; PHASE="$2"; shift 2 ;;
    --iterations)     require_value "$1" "${2:-}"; ITERATIONS="$2"; shift 2 ;;
    --engine)         require_value "$1" "${2:-}"; ENGINE="$2"; shift 2 ;;
    --model)          require_value "$1" "${2:-}"; MODEL="$2"; shift 2 ;;
    --journal-file)   require_value "$1" "${2:-}"; JOURNAL_FILE="$2"; shift 2 ;;
    --exclude-files)  require_value "$1" "${2:-}"; EXCLUDE_FILE="$2"; shift 2 ;;
    --max-prompt-kb)  require_value "$1" "${2:-}"; MAX_PROMPT_KB="$2"; shift 2 ;;
    --max-concurrent) require_value "$1" "${2:-}"; MAX_CONCURRENT="$2"; shift 2 ;;
    --standalone)     MODE="standalone"; shift ;;
    --dry-run)        DRY_RUN=true; shift ;;
    *)                PROJECT_DIR="$1"; shift ;;
  esac
done

# Engine-specific model defaults
if [[ -z "$MODEL" ]]; then
  case "$ENGINE" in
    codex)  MODEL="gpt-5.4" ;;
    gemini) MODEL="" ;;  # gemini uses its own default
    *)      MODEL="gpt-5.4" ;;
  esac
fi

# Resolve script paths BEFORE cd to PROJECT_DIR — $0 may be relative to original CWD
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHARED_ENGINES="${SCRIPT_DIR}/../../shared/engines"
ENGINE_SCRIPT="${SHARED_ENGINES}/${ENGINE}.sh"
# shellcheck source=_concurrency_check.sh disable=SC1091
source "${SHARED_ENGINES}/_concurrency_check.sh"

# Load the git-safety scanner (declares git_safety_scan_since, no side effects)
# shellcheck source=git_safety_scan.sh disable=SC1091
source "$SCRIPT_DIR/git_safety_scan.sh"

# Load the exclude-files enforcer (declares bug_hunt_exclude_enforce)
# shellcheck source=exclude_enforce.sh disable=SC1091
source "$SCRIPT_DIR/exclude_enforce.sh"

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
cd "$PROJECT_DIR"
PROJECT_DIR="$(pwd)"  # normalize to absolute for child processes

# shellcheck disable=SC1090
# Source API keys
source ~/.env.secrets 2>/dev/null || true

if [[ "$ENGINE" == "claude" ]]; then
  echo "ERROR: claude engine should use the Agent tool directly, not hunt.sh"
  exit 1
fi

if [[ ! -f "$ENGINE_SCRIPT" ]]; then
  echo "ERROR: unknown engine '${ENGINE}' — no script at ${ENGINE_SCRIPT}"
  echo "Available: $(find "${SHARED_ENGINES}/" -name '*.sh' -exec basename {} .sh \; 2>/dev/null | tr '\n' ' ')"
  exit 1
fi

check_engine_concurrency "$MAX_CONCURRENT"

# Prewarm ubs modules on the host so any in-iteration `ubs` call doesn't pay
# download cost inside the codex sandbox (reads as a hang). Idempotent; the
# prewarm script consults `ubs doctor` and only downloads when modules are
# missing. Best-effort: a prewarm failure must not block dispatch.
bash "$SCRIPT_DIR/prewarm_ubs.sh" || true

# Build AGENTS.md context — extract safety-relevant sections only (skip verbose
# toolchain/architecture that the engine doesn't need). Uses keyword matching on
# section headers rather than exact names for cross-project compatibility.
AGENTS_CONTEXT=""
if [[ -f "AGENTS.md" ]]; then
  AGENTS_CONTEXT="$(awk '
    BEGIN { printing=0 }
    /^##+ .*(Safety|Rules|Constraint|Quality|Gate|Discipline|Convention|Git|Workflow|Style)/ { printing=1 }
    /^##+ / && printing && !/Safety|Rules|Constraint|Quality|Gate|Discipline|Convention|Git|Workflow|Style/ { printing=0 }
    printing { print }
  ' AGENTS.md)"
  # Fallback: if extraction got <5 lines, use first 80 lines
  if [[ $(echo "$AGENTS_CONTEXT" | wc -l) -lt 5 ]]; then
    AGENTS_CONTEXT="$(head -80 AGENTS.md)"
  fi
  # Hard cap: never exceed 4KB for AGENTS.md portion
  agents_bytes=$(echo "$AGENTS_CONTEXT" | wc -c | tr -d ' ')
  if (( agents_bytes > 4096 )); then
    AGENTS_CONTEXT="$(echo "$AGENTS_CONTEXT" | head -80)"
  fi
fi

# Read journal context — cap at 2KB to leave room for AGENTS.md + prompt
JOURNAL_CONTEXT=""
if [[ -n "$JOURNAL_FILE" && -f "$JOURNAL_FILE" ]]; then
  full_journal="$(cat "$JOURNAL_FILE")"
  journal_bytes=$(echo "$full_journal" | wc -c | tr -d ' ')
  if (( journal_bytes > 2048 )); then
    # Priority order for trimming: unexplored areas > patterns > recent results
    # "Areas not yet examined" is the most valuable for directing the engine
    areas=$(echo "$full_journal" | grep -A15 "^### Areas not yet examined" | head -15 || true)
    patterns=$(echo "$full_journal" | grep -A15 "^### Bug patterns" | head -15 || true)
    recent=$(echo "$full_journal" | tail -20)
    JOURNAL_CONTEXT=""
    [[ -n "$patterns" ]] && JOURNAL_CONTEXT="${patterns}
"
    [[ -n "$areas" ]] && JOURNAL_CONTEXT="${JOURNAL_CONTEXT}
${areas}
"
    JOURNAL_CONTEXT="${JOURNAL_CONTEXT}
(Earlier iteration details trimmed — ${journal_bytes} bytes total)

${recent}"
    # Final byte check — hard cap even after smart trimming
    trimmed_bytes=$(echo "$JOURNAL_CONTEXT" | wc -c | tr -d ' ')
    if (( trimmed_bytes > 2048 )); then
      JOURNAL_CONTEXT=$(echo "$JOURNAL_CONTEXT" | head -c 2048)
      JOURNAL_CONTEXT="${JOURNAL_CONTEXT}
...(truncated to 2KB)"
    fi
  else
    JOURNAL_CONTEXT="$full_journal"
  fi
fi

# Read excluded files list if provided
EXCLUDE_CONTEXT=""
if [[ -n "$EXCLUDE_FILE" && -f "$EXCLUDE_FILE" ]]; then
  EXCLUDE_CONTEXT="DO NOT MODIFY these files (reserved by other agents):
$(cat "$EXCLUDE_FILE")
"
fi

# Anti-feature-creep guardrails — appended to every phase prompt.
# The .beads/ directive is prompt-only enforcement: Codex's workspace-write
# sandbox (codex-cli 0.132.0) makes the whole project tree writable and has
# no per-subdirectory write-exclusion (writable_roots only adds paths; there
# is no CODEX_SANDBOX_EXCLUDE / deny rule), so .beads/ cannot be sandbox-
# protected. See bd-qq6.
CREEP_GUARD='

CRITICAL CONSTRAINTS — you are a BUG HUNTER, not a feature developer:
- DO NOT add new dependencies, packages, or imports that did not exist before
- DO NOT add new CI/CD workflows, GitHub Actions, or automation configs
- DO NOT add new configuration files, docker-compose services, or infrastructure
- DO NOT refactor code that is not broken — only fix actual bugs
- DO NOT add features, improve ergonomics, or "enhance" working code
- If a file has no bugs, leave it untouched — do not "improve" it
- Only create new files if they are TEST files that verify your bug fix
- DO NOT run br, bv, beads, or any bead-management commands
- DO NOT read, list, or modify .beads/ — it is agent-coordination metadata, not code under review
Any violation of these constraints will be reverted.'

# Git safety — appended to every engine prompt, NON-NEGOTIABLE.
# Rationale: parallel bug-hunt/swarm-build agents may commit to the same branch
# from other worktrees. Prior incidents:
#   2026-04-17: codex amended another agent's commit, then reverted as "scope"
#   2026-04-18: codex cherry-picked 10 Dependabot PRs onto local dev
#   2026-04-18: codex ran a rebase with 2 amends during Phase 2
# Prompt-only enforcement has failed repeatedly — the orchestrator also runs a
# reflog scan after every iteration (see git_safety_scan.sh).
GIT_SAFETY='

Git safety — NON-NEGOTIABLE. The orchestrator owns the branch context.
You never move HEAD or fetch refs; the orchestrator handles all branch
switching and remote sync. Engines stay on the branch they were dispatched on.

- DO NOT run git commit --amend under any circumstances.
- DO NOT run git revert, git reset, git rebase (including rebase -i),
  or git cherry-pick.
- DO NOT run git checkout (any form) or git switch (any form). You stay
  on the branch the orchestrator dispatched you on. Even a same-branch
  checkout is forbidden — touching HEAD is the orchestrator''s job.
- DO NOT run git pull (any form, including --ff-only or --rebase).
- DO NOT run git fetch (any form). The orchestrator fetches refs.
- DO NOT fetch or cherry-pick from Dependabot branches, PR branches,
  refs/pull/*, or any remote ref other than the branch you are on.
- DO NOT force-push or git push --force-with-lease.
- DO NOT tidy, squash, or reorder your own commits. If your work would
  benefit from reordering or squashing, the orchestrator will handle
  that — leave it alone.
- If you need to fix something, create a NEW commit on top of HEAD.
- Parallel bug-hunt agents may be committing to the same branch from
  other worktrees. Treat every existing commit as potentially
  another-agent-authored and immutable.

Consequences: the orchestrator runs a reflog scan after every iteration
and asserts HEAD has not moved off the dispatch branch. Any rebase /
cherry-pick / amend / reset / revert / checkout / switch / pull / fetch
entry — or any branch drift — triggers a violation report, and the
iteration may be rolled back. Work done via forbidden operations can be lost.'

# Phase prompts
PHASE1_PROMPT='I want you to sort of randomly explore the code files in this project, choosing code files to deeply investigate and understand and trace their functionality and execution flows through the related code files which they import or which they are imported by.

Once you understand the purpose of the code in the larger context of the workflows, I want you to do a super careful, methodical, and critical check with "fresh eyes" to find any obvious bugs, problems, errors, issues, silly mistakes, etc. and then systematically and meticulously and intelligently correct them.

Be sure to comply with ALL rules in AGENTS.md and ensure that any code you write or revise conforms to the best practice guides referenced in the AGENTS.md file. Use ultrathink.'"$CREEP_GUARD""$GIT_SAFETY"

PHASE2_PROMPT='Turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues, etc. and carefully diagnose their underlying root causes using first-principle analysis and then fix or revise them if necessary. Do not restrict yourself to the latest commits, cast a wider net and go super deep! Use ultrathink.'"$CREEP_GUARD""$GIT_SAFETY"

PHASE3_PROMPT='Carefully read over all recently modified code (check git log and git diff for recent changes) with "fresh eyes" looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover. Use ultrathink.'"$CREEP_GUARD""$GIT_SAFETY"

# Run prompt through the selected engine
run_engine() {
  local prompt="$1"
  local prompt_file
  prompt_file=$(mktemp /tmp/bug-hunt-prompt.XXXXXX)
  echo "$prompt" > "$prompt_file"

  local engine_args=(--prompt-file "$prompt_file")
  [[ -n "$MODEL" ]] && engine_args+=(--model "$MODEL")

  local rc=0
  bash "$ENGINE_SCRIPT" "${engine_args[@]}" "$PROJECT_DIR" 2>&1 || rc=$?
  rm -f "$prompt_file"
  return $rc
}

phase_name() {
  case "$1" in
    1) echo "Explore & Fix" ;;
    2) echo "Review Others" ;;
    3) echo "Self-Review" ;;
  esac
}

phase_prompt() {
  case "$1" in
    1) echo "$PHASE1_PROMPT" ;;
    2) echo "$PHASE2_PROMPT" ;;
    3) echo "$PHASE3_PROMPT" ;;
  esac
}

# Assemble full prompt with all context layers
build_prompt() {
  local phase_num=$1
  local prompt
  prompt="$(phase_prompt "$phase_num")"
  local full=""

  # Layer 1: AGENTS.md rules
  if [[ -n "$AGENTS_CONTEXT" ]]; then
    full="Follow these project rules strictly:

${AGENTS_CONTEXT}

---

"
  fi

  # Layer 2: File exclusions from other agents
  if [[ -n "$EXCLUDE_CONTEXT" ]]; then
    full="${full}${EXCLUDE_CONTEXT}

---

"
  fi

  # Layer 3: Hunt journal from prior iterations
  if [[ -n "$JOURNAL_CONTEXT" ]]; then
    full="${full}## Hunt Journal from Prior Iterations

${JOURNAL_CONTEXT}

DO NOT re-examine files already marked as fixed or clean above.
Focus on unexplored areas and look for the same bug patterns in new files.

---

"
  fi

  # Layer 4: The actual phase prompt
  full="${full}${prompt}"

  echo "$full"
}

snapshot_untracked() {
  local out_file=$1
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    : > "$out_file"
    return 0
  fi
  git ls-files --others --exclude-standard 2>/dev/null | sort > "$out_file"
}

count_paths() {
  sed '/^$/d' | sort -u | wc -l | tr -d ' '
}

new_untracked_since() {
  local before_file=$1
  local after_file=$2
  comm -13 "$before_file" "$after_file"
}

working_tree_paths_since() {
  local before_untracked_file=$1
  local after_untracked_file=$2
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git diff --name-only 2>/dev/null || true
    git diff --cached --name-only 2>/dev/null || true
  fi
  new_untracked_since "$before_untracked_file" "$after_untracked_file"
}

committed_paths_since() {
  local before_sha=$1
  [[ "$before_sha" != "none" ]] || return 0
  git diff --name-only "$before_sha"..HEAD 2>/dev/null || true
}

new_file_paths_since() {
  local before_sha=$1
  local before_untracked_file=$2
  local after_untracked_file=$3
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ "$before_sha" != "none" ]]; then
      git diff --name-only --diff-filter=A "$before_sha"..HEAD 2>/dev/null || true
    fi
    git diff --cached --name-only --diff-filter=A 2>/dev/null || true
  fi
  new_untracked_since "$before_untracked_file" "$after_untracked_file"
}

run_single() {
  local phase_num=$1
  local name
  name="$(phase_name "$phase_num")"
  local full_prompt
  full_prompt="$(build_prompt "$phase_num")"

  local before_sha
  before_sha=$(git rev-parse HEAD 2>/dev/null || echo "none")
  local before_untracked_file after_untracked_file
  before_untracked_file=$(mktemp -t bug-hunt-untracked-before.XXXXXX)
  after_untracked_file=$(mktemp -t bug-hunt-untracked-after.XXXXXX)
  snapshot_untracked "$before_untracked_file"

  echo ""
  echo "=== Phase ${phase_num} (${name}) ==="
  echo ""

  local prompt_bytes
  prompt_bytes=$(echo "$full_prompt" | wc -c | tr -d ' ')
  local prompt_kb=$(( prompt_bytes / 1024 ))
  local max_bytes=$(( MAX_PROMPT_KB * 1024 ))

  if $DRY_RUN; then
    rm -f "$before_untracked_file" "$after_untracked_file"
    echo "[DRY RUN] Prompt layers:"
    echo "  AGENTS.md: $([ -n "$AGENTS_CONTEXT" ] && echo "yes ($(echo "$AGENTS_CONTEXT" | wc -l | tr -d ' ') lines)" || echo "no")"
    echo "  Exclusions: $([ -n "$EXCLUDE_CONTEXT" ] && echo "yes" || echo "no")"
    echo "  Journal: $([ -n "$JOURNAL_CONTEXT" ] && echo "yes ($(echo "$JOURNAL_CONTEXT" | wc -l | tr -d ' ') lines)" || echo "no")"
    echo "  Phase prompt: $(echo "$phase_num" | sed 's/1/Explore \& Fix/;s/2/Review Others/;s/3/Self-Review/')"
    echo "  Total: ${prompt_kb}KB / ${MAX_PROMPT_KB}KB budget"
    echo ""
    return 0
  fi

  # Warn if prompt exceeds budget
  if (( prompt_bytes > max_bytes )); then
    echo "WARNING: prompt is ${prompt_kb}KB, exceeds ${MAX_PROMPT_KB}KB budget — engine may have issues"
  fi

  # Capture BEFORE running engine so the reflog scan knows its window
  # and so the HEAD-branch assertion knows where the engine should stay.
  local iteration_start_epoch iteration_start_branch
  iteration_start_epoch=$(date +%s)
  iteration_start_branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")

  # Run engine
  if run_engine "$full_prompt"; then
    echo ""
  else
    local exit_code=$?
    echo "WARNING: ${ENGINE} exited with code ${exit_code}"
  fi

  # Post-iteration git-safety scan. Surfaces forbidden reflog ops and any
  # HEAD-branch drift loudly. Orchestrator (SKILL.md §4c) decides
  # accept / flag-and-continue / revert.
  local violations
  violations=$(git_safety_scan_since "$iteration_start_epoch" "$iteration_start_branch")
  if [[ -n "$violations" ]]; then
    echo ""
    echo "!!! GIT SAFETY VIOLATION DETECTED !!!"
    echo "Reflog entries newer than iteration start that match forbidden ops:"
    echo "$violations"
    echo ""
    echo "Orchestrator: review the reflog above against SKILL.md §4c decision"
    echo "matrix (accept / flag-and-continue / revert). before_sha=${before_sha}"
    echo ""
  fi

  # Layer-3 enforcement: revert / surgical-restore any engine commits that
  # touched paths on --exclude-files. Layer-2 ran first so the reflog scan
  # observed the engine's reflog, not the remediation's.
  if [[ -n "$EXCLUDE_FILE" && -f "$EXCLUDE_FILE" && "$before_sha" != "none" ]]; then
    bug_hunt_exclude_enforce "$before_sha" "$EXCLUDE_FILE"
  fi

  # Report changes
  local changed committed total
  snapshot_untracked "$after_untracked_file"
  changed=$(working_tree_paths_since "$before_untracked_file" "$after_untracked_file" | count_paths)
  committed=$(committed_paths_since "$before_sha" | count_paths)
  total=$((changed + committed))

  echo ""
  echo "--- Iteration Results ---"
  echo "Files touched: ${total}"
  if [[ $total -gt 0 ]]; then
    echo "Modified files:"
    working_tree_paths_since "$before_untracked_file" "$after_untracked_file" | sort -u
    committed_paths_since "$before_sha"
    echo ""
    git diff --stat 2>/dev/null | tail -10
    git diff --cached --stat 2>/dev/null | tail -10
    git diff --stat "$before_sha"..HEAD 2>/dev/null | tail -10

    # Feature creep detection: flag new non-test files
    local new_files
    new_files=$(new_file_paths_since "$before_sha" "$before_untracked_file" "$after_untracked_file" | sort -u)
    if [[ -n "$new_files" ]]; then
      local suspect
      suspect=$(echo "$new_files" | grep -v -E '(test_|_test\.|\.test\.|spec\.|tests/)' || true)
      if [[ -n "$suspect" ]]; then
        echo ""
        echo "WARNING: Feature creep? New non-test files added:"
        echo "$suspect"
        echo "Review these — bug fixes rarely need new files outside tests/"
      fi
    fi
  fi
  rm -f "$before_untracked_file" "$after_untracked_file"
  echo "--- End Results ---"
}

# ── Standalone mode: run all phases x iterations (no journal accumulation) ──
run_standalone() {
  local start_sha
  start_sha=$(git rev-parse HEAD 2>/dev/null || echo "no-git")
  local total_changed=0
  local fail_streak=0

  if [[ -n "$PHASE" ]]; then
    local phases=("$PHASE")
  else
    local phases=(1 2 3)
  fi

  echo "bug-hunt (standalone): ${#phases[@]} phase(s), ${ITERATIONS} iter each, engine=${ENGINE}, model=${MODEL:-default}"
  echo "Project: ${PROJECT_DIR}"
  echo ""

  for p in "${phases[@]}"; do
    for ((i = 1; i <= ITERATIONS; i++)); do
      local name
      name="$(phase_name "$p")"
      echo ""
      echo "=== Phase ${p} (${name}) — Iteration ${i}/${ITERATIONS} ==="

      local before_sha
      before_sha=$(git rev-parse HEAD 2>/dev/null || echo "none")
      local before_untracked_file after_untracked_file
      before_untracked_file=$(mktemp -t bug-hunt-untracked-before.XXXXXX)
      after_untracked_file=$(mktemp -t bug-hunt-untracked-after.XXXXXX)
      snapshot_untracked "$before_untracked_file"
      local full_prompt
      full_prompt="$(build_prompt "$p")"

      if $DRY_RUN; then
        rm -f "$before_untracked_file" "$after_untracked_file"
        echo "[DRY RUN] Would run ${ENGINE} ($(echo "$full_prompt" | wc -c | tr -d ' ') bytes)"
        continue
      fi

      # Budget check
      local sa_bytes
      sa_bytes=$(echo "$full_prompt" | wc -c | tr -d ' ')
      if (( sa_bytes > MAX_PROMPT_KB * 1024 )); then
        echo "WARNING: prompt is $((sa_bytes / 1024))KB, exceeds ${MAX_PROMPT_KB}KB budget"
      fi

      local iteration_start_epoch iteration_start_branch
      iteration_start_epoch=$(date +%s)
      iteration_start_branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")

      if run_engine "$full_prompt"; then
        fail_streak=0
      else
        echo "WARNING: ${ENGINE} failed"
        fail_streak=$((fail_streak + 1))
        rm -f "$before_untracked_file" "$after_untracked_file"
        if [[ $fail_streak -ge 3 ]]; then
          echo "ERROR: 3 consecutive failures — aborting"
          exit 1
        fi
        continue
      fi

      # Post-iteration git-safety scan (same as run_single)
      local violations
      violations=$(git_safety_scan_since "$iteration_start_epoch" "$iteration_start_branch")
      if [[ -n "$violations" ]]; then
        echo ""
        echo "!!! GIT SAFETY VIOLATION DETECTED !!!"
        echo "$violations"
        echo "before_sha=${before_sha}"
        echo ""
      fi

      # Layer-3 enforcement (same as run_single)
      if [[ -n "$EXCLUDE_FILE" && -f "$EXCLUDE_FILE" && "$before_sha" != "none" ]]; then
        bug_hunt_exclude_enforce "$before_sha" "$EXCLUDE_FILE"
      fi

      local changed committed total
      snapshot_untracked "$after_untracked_file"
      changed=$(working_tree_paths_since "$before_untracked_file" "$after_untracked_file" | count_paths)
      committed=$(committed_paths_since "$before_sha" | count_paths)
      total=$((changed + committed))
      total_changed=$((total_changed + total))
      echo "  Files touched: ${total}"

      # Feature creep detection (same as single mode)
      local new_files
      new_files=$(new_file_paths_since "$before_sha" "$before_untracked_file" "$after_untracked_file" | sort -u)
      if [[ -n "$new_files" ]]; then
        local suspect
        suspect=$(echo "$new_files" | grep -v -E '(test_|_test\.|\.test\.|spec\.|tests/)' || true)
        if [[ -n "$suspect" ]]; then
          echo "  WARNING: Feature creep? New non-test files: $suspect"
        fi
      fi
      rm -f "$before_untracked_file" "$after_untracked_file"
    done
  done

  echo ""
  echo "========================================"
  echo "bug-hunt complete"
  echo "========================================"
  echo "Phases: ${phases[*]}"
  echo "Total files touched: ${total_changed}"

  if [[ "$start_sha" != "no-git" ]]; then
    echo ""
    git diff --stat "$start_sha"..HEAD 2>/dev/null || true
    git diff --stat 2>/dev/null || true
    echo ""
    echo "Recommended: ubs \$(git diff --name-only ${start_sha}..HEAD)"
  fi
}

# ── Dispatch ──
if [[ "$MODE" == "standalone" ]]; then
  run_standalone
else
  if [[ -z "$PHASE" ]]; then
    echo "ERROR: --phase required in single-iteration mode (use --standalone for full run)"
    exit 1
  fi
  run_single "$PHASE"
fi
