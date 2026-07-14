---
name: bug-hunt
description: Run a multi-phase bug hunt with Codex, Gemini, or Claude.
when-to-use:
- bug hunt, find bugs, codex hunt, hunt for bugs
- When you want repeated explore, fix, and review passes
user_invocable: true
allowed-tools: Bash(codex:*)|Bash(gemini:*)|Bash(source:*)|Bash(cat:*)|Bash(git:*)|Read|Write|Glob|Agent
category: code
---

# /bug-hunt — Autonomous Multi-Phase Bug Hunting

Run a pluggable engine (Codex, Gemini, or Claude) through a structured 3-phase
bug hunting routine against the current working directory. Each phase runs N
iterations (default 3). A rolling hunt journal accumulates across iterations via
Agent Mail threads, so each engine run builds on what previous runs discovered.

## Arguments

```
/bug-hunt                              # full run: 3 phases x 3 iterations (9 total)
/bug-hunt --engine gemini              # use Gemini CLI instead of Codex
/bug-hunt --engine claude              # use Claude Code subagent (worktree isolation)
/bug-hunt --iterations 5               # 5 iterations per phase (15 total)
/bug-hunt --phase 2                    # run only phase 2 (review others' code)
/bug-hunt --phase 1 --iterations 2     # 2 iterations of phase 1 only
/bug-hunt --dry-run                    # print prompts without executing
/bug-hunt --no-mail                    # skip Agent Mail (solo mode, local journal only)
```

## Phases

| # | Name | Focus |
|---|------|-------|
| 1 | **Explore & Fix** | Randomly explore code files, trace execution flows, find and fix bugs |
| 2 | **Review Others** | Review code written by other agents, deep root-cause analysis |
| 3 | **Self-Review** | Fresh-eyes review of all code just written/modified |

## Workflow

### 1. Parse Arguments

Extract from `$ARGUMENTS`:
- `--engine <codex|gemini|claude>` (default: codex)
- `--iterations N` (default: 3)
- `--phase N` (1, 2, or 3 — omit to run all phases)
- `--dry-run` flag
- `--model <model>` (default: engine-specific — codex=gpt-5.4, gemini=default)
- `--no-mail` flag (skip Agent Mail)

### 2. Register & Create Hunt Thread

Unless `--no-mail` is set:

1. Call `macro_start_session` with:
   - `human_key`: current working directory path
   - `program`: `claude-code`
   - `model`: your model name
   - `task_description`: `"bug-hunt: <phases> x <iterations> iterations"`

   **Save the response.** Hold `agent.name` and `registration_token` for the
   entire session — needed to deregister cleanly in step 5.

2. **Set open contact policy** so broadcasts don't fail as new agents register:
   - Call `set_contact_policy` with `policy: "open"` (or `auto_accept: true`)
   - This prevents the contact-approval explosion seen in long sessions

3. Check inbox. Acknowledge pending messages. Note active agents and their
   file reservations.

4. **Check for prior hunt history**: Call `fetch_topic` with topic `bug-hunt`
   to see if past hunts found recurring patterns or known-fragile areas.
   Include a 1-line summary of prior findings in the first engine prompt.

5. Create a hunt thread ID: `bug-hunt-YYYY-MM-DD-HHMM`

6. Announce the hunt via `send_message`:
   - thread_id: the hunt thread ID
   - topic: `bug-hunt`
   - body: phases, iteration count, target directory, any prior-hunt context

**Agent Mail isolation**: Only this Claude Code session registers with Agent
Mail. Engine sub-processes do NOT register — they have no MCP access. All
Agent Mail communication flows through the orchestrating Claude Code session.

### 3. Build Context

Before running phases, gather context for the engine:
- Read `AGENTS.md` to extract rules the engine must follow
- Record `start_sha=$(git rev-parse HEAD)` — needed for the pristine-tree
  falsification in step 4c
- Note the current git branch and recent commits
- If Agent Mail is active, note file reservations and prepend
  "DO NOT MODIFY these files: ..." to engine prompts
- **Pre-flight concurrency gate before dispatch**. The shared helper blocks
  if active host-wide `codex exec` + `gemini -p` processes are already at
  the cap (default `2`, override with `SWARM_MAX_CONCURRENT` or
  `hunt.sh --max-concurrent N`). If the check refuses, stop before phase
  dispatch so dry-run and real runs fail the same way.
- **Record quality-gate baseline** — identify the project's test command
  (from AGENTS.md / README / `package.json` / `pyproject.toml`) and run it
  once. Persist the failing-test IDs and pass/fail counts to a per-session
  baseline file:
  ```bash
  TEST_BASELINE="$(mktemp -t bug-hunt-baseline.XXXXXX)"
  # run project test command, capture failing-test IDs + pass/fail counts to $TEST_BASELINE
  ```
  A file (not just conversation context) because the orchestrator may be
  compacted between iterations and lose in-context memory. You will diff
  every post-iteration run against this file. If the project has no test
  suite, write `NO_TEST_SUITE` to `$TEST_BASELINE` and fall back to
  comparing `git status` + manual smoke checks.

  Bug-hunt expects deltas — some baseline-failing tests SHOULD flip to
  passing (that's the point). The regression rule is one-directional:
  baseline-passing → now-failing is a regression; baseline-failing →
  now-passing is good. Tests the engine skipped or deleted are a judgment
  call: "the bug was in the test" is sometimes true but usually suspicious.

**Git safety block** (appended verbatim to every engine prompt in every phase — handled
in `hunt.sh` alongside the feature-creep guard):

```
Git safety — NON-NEGOTIABLE:
- DO NOT run git commit --amend under any circumstances.
- DO NOT run git revert, git reset, git rebase, or git cherry-pick.
- DO NOT force-push or git push --force-with-lease.
- If you need to fix something, create a NEW commit on top of HEAD.
- Parallel bug-hunt agents may be committing to the same branch from
  other worktrees. Treat every existing commit as potentially
  another-agent-authored and immutable.
```

This is non-negotiable for all 3 phases including self-review — reviewers have strong
incentive to rewrite history ("let me just amend that fix in") and must be blocked.

### 4. Execute Phases — The Accumulating Loop

This is the core innovation. Instead of running `hunt.sh` as a monolithic
script, Claude Code orchestrates the loop directly so it can inject Agent Mail
context between iterations.

**For each phase, for each iteration:**

#### 4a. Build journal context

If this is not the first iteration:
- Call `summarize_thread` on the hunt thread to get an LLM-compressed
  summary of all findings so far
- **Hard cap the journal at 2KB** — if `summarize_thread` returns more
  (or the `--no-mail` local journal has grown past 2KB), first try
  `hr-compress .bug-hunt/journal.md --query "areas not yet examined, bug patterns"`
  (`~/.local/bin/hr-compress`) — it dedups repeated entries while keeping
  distinctive lines. If still over 2KB or `hr-compress` is unavailable,
  keep only: "Areas not yet examined" > "Bug patterns" > last 20 lines.
  Engines hit input limits when journal + AGENTS.md + prompt exceeds ~8KB.
- The summary becomes a `HUNT JOURNAL` block prepended to the engine prompt:

```
## Hunt Journal (iterations 1-3 complete)

### Files already examined & fixed
- skills/done/scripts/reduce.sh — fixed unguarded pipeline exit
- setup/categories.js — fixed stale taxonomy enum

### Files examined, no issues found
- skills/codex/SKILL.md, skills/groom/SKILL.md

### Bug patterns found so far
- Unguarded `|| true` masking failures (2 instances)
- Missing `set -euo pipefail` in scripts (1 instance)

### Areas not yet examined
- tests/ directory, skills/shared/

DO NOT re-examine files already marked as fixed or clean above.
Focus on unexplored areas and look for the same bug patterns in new files.
```

If `--no-mail`, read the local journal from `.bug-hunt/journal.md` in the
project directory instead. **Not `/tmp/bug-hunt-journal.md`** — that path is
shared across all projects on the host, and two `--no-mail` hunts on
different repos will stomp each other's journals. (Real failure 2026-04-26:
a parallel hunt overwrote the active journal mid-iteration, sending the
engine off-script with someone else's "files already examined" context.)
Project-local journals scope naturally per-worktree, so parallel hunts on
different repos (or different worktrees of the same repo) can't interfere.

#### 4b. Run Engine

For codex/gemini engines, call `hunt.sh` with stdout/stderr redirected to a
per-iteration log file (NOT piped to `tail`):
```bash
LOGFILE=".bug-hunt/phase${P}-iter${ITER}.log"
bash "$SKILL_DIR/scripts/hunt.sh" \
  --phase <P> \
  --engine <ENGINE> \
  --model <M> \
  --journal-file .bug-hunt/journal.md \
  [--dry-run] > "$LOGFILE" 2>&1
tail -120 "$LOGFILE"
```

**Why redirect-to-file, not pipe-to-tail**: a `producer-pipe-to-tail` pipeline blocks
the engine wrapper once stdout exceeds the OS pipe buffer (~16KB on
macOS) if the consumer ever stalls or gets orphaned by the harness.
Observed 2026-04-26 in a swarm-build session: codex.sh wrapper alive
with `lsof` showing fd 1 → `PIPE 16384` (full), no codex child running,
tail consumer never produced output. Redirecting to a file removes the
pipe-buffer cap (filesystem has none); the orchestrator reads the
completed log afterward, and full output is preserved for post-mortem.

For claude engine, use the Agent tool with `isolation: worktree`.

Timeout: 600000ms (10 minutes).

#### 4c. Capture iteration results

After the engine completes:
- Run `git diff --stat` and `git diff --name-only` to capture what changed
- Build an iteration report:

```markdown
## Phase <N> Iteration <M> Results
- Files modified: file1.sh, file2.js
- Changes: <git diff --stat summary>
- Bugs fixed: <extract from engine output if possible>
```

Then **re-run the project's full quality gates from the orchestrator**. Use
the same command you baselined in step 3. Do this every iteration in every
phase. Save the post-iteration pass/fail set as `post_test_P<phase>I<iter>`.

**Diff test results against the baseline**, not against the engine's
summary:
- Same set of failing tests as baseline → no regression.
- Baseline failure that now passes → good, the bug was fixed.
- New failing test that was passing in baseline → **regression**, even if
  the engine called it "pre-existing" or "unrelated." Treat any claim of
  "pre-existing failure" as falsifiable. Verify on a pristine `start_sha`
  tree via a throwaway git worktree — this works whether the engine
  committed its changes or left them uncommitted. `git stash` is the wrong
  tool here because it can't capture committed changes.
  ```bash
  PRISTINE="$(mktemp -u -t bug-hunt-pristine.XXXXXX)"
  git worktree add "$PRISTINE" "$start_sha"
  # Project-local deps (node_modules, .venv) won't exist in the worktree.
  # Run whatever install the baseline depends on, or scope the pristine
  # re-run to ONLY the failing test in isolation (e.g.
  # `pytest path/to/test.py::test_name`) rather than the full suite —
  # the point is to confirm the test fails independent of the
  # iteration's changes, not to reproduce the whole suite.
  (cd "$PRISTINE" && <install deps if needed> && <same test command as baseline>)
  git worktree remove --force "$PRISTINE"
  ```
  `--force` on removal handles untracked artifacts (e.g. `.pytest_cache/`,
  `.venv/`) that tests commonly drop outside `.gitignore`, which would
  otherwise make `worktree remove` refuse. Only if the test still fails
  on the pristine tree is the "pre-existing" claim valid.
- Test disappeared (engine skipped or deleted it) → orchestrator judgment.
  If the engine has a defensible reason the test was wrong, fine. Absent
  that, treat deletion as equivalent to a regression — re-queue the area
  with instructions not to silence the test.

If a regression is confirmed, do not let it stand: either feed it into the
next iteration's prompt as a required fix, or `git revert <sha>` the
offending commit (forward-only — creates a new revert commit on top of
HEAD). The orchestrator is NOT bound by the Layer 5 git-safety block that
restricts the engine, but prefer `git revert` over `git reset --hard` so
parallel agents don't lose their in-flight work.

Then **run a git-safety scan against the reflog**. The engine prompt bans
rebase, cherry-pick, amend, reset, revert, force-push, and fetching from
PR/Dependabot refs, but prompt-only enforcement has failed before
(2026-04-18 had codex cherry-pick 10 Dependabot PRs and, separately,
run a rebase with 2 amends despite the block). `hunt.sh` surfaces any
forbidden reflog entries immediately after the engine run — the
orchestrator must review them and make a documented judgment:

```bash
# hunt.sh already captures iteration_start_epoch before run_engine and
# scans via git_safety_scan_since after. If the scan fires, you'll see
# a "!!! GIT SAFETY VIOLATION DETECTED !!!" block in the iteration log.
```

Decision matrix:
- **Accept** — violation was benign (e.g. cherry-pick of commits origin
  already had; reflog noise but the tree is unchanged from a clean
  forward-only iteration). Document in the journal and continue.
- **Flag-and-continue** — violation rewrote commits, but the result looks
  legitimate and no other agent's work was touched. Post a loud warning
  to the hunt thread, reinforce the prompt next iteration, continue.
- **Revert** — violation touched another agent's commits, lost work, or
  the post-op diff is unrecognizable. Use `git revert <sha>` forward-only
  (never `git reset --hard` — parallel agents may lose in-flight work).

Post the decision to the hunt thread with subject
`"P<phase>I<iter>: git-safety violation — <decision>"` and a 1-line
reason. The scan output itself belongs in the body, not the journal
summary, so summaries don't balloon.

#### 4d. Post to hunt journal

If Agent Mail is active:
- Call `send_message` with:
  - thread_id: the hunt thread ID
  - topic: `bug-hunt`
  - subject: `"P<phase>I<iter>: <brief summary>"`
  - body: the iteration report from 4c

If `--no-mail`:
- Ensure the directory exists: `mkdir -p .bug-hunt`
- Append the iteration report to `.bug-hunt/journal.md`
- Add `.bug-hunt/` to `.gitignore` if not already ignored (the journal is
  transient session state and shouldn't be committed)

#### 4e. Between-phase coordination (after all iterations of a phase)

If Agent Mail is active:
- Call `fetch_inbox` — respond to any direct messages
- If another agent reports conflicts, pause and coordinate
- Post a phase-completion summary to the hunt thread

### 5. Report Results

After all phases complete:
- Show total files changed across all iterations
- Show condensed `git diff --stat` of all changes since start
- Suggest running quality gates: `ubs $(git diff --name-only)`

If Agent Mail is active:
- Post final summary to hunt thread (topic: `bug-hunt`)
- Call `summarize_thread` on the hunt thread to produce a final digest
- Present the digest to the user
- Check inbox one final time and respond to anything pending
- **Release reservations and deregister** (only if this session registered):
  - `release_file_reservations(project_key, agent_name)`
  - `deregister_agent(project_key, agent_name, registration_token)` using the
    token saved in step 2. Best-effort: a failed call must not block exit —
    log and continue.
  - **Deregister, don't retire** — retirement leaves the agent in the roster
    and accumulates contact-approval rows that block future broadcasts.
    Never call `hard_delete_agent` from here; it irreversibly destroys
    message history and is reserved for explicit human purge requests.

**Clean up temp paths**: `rm -f "${TEST_BASELINE:?}"` (the `:?` guards against
an accidentally-unset variable turning this into a disaster), then
`git worktree prune` to drop any stale worktree registrations from
falsification runs that didn't reach their own `git worktree remove` (e.g.
an iteration errored before cleanup). Without `prune`, `git worktree list`
accumulates ghost entries pointing at deleted directories.

### 6. Run hunt.sh for individual iterations

The bash script `$SKILL_DIR/scripts/hunt.sh` handles a **single iteration**
of engine execution. Claude Code calls it repeatedly, injecting journal context
between calls.

```bash
# Single iteration with journal context injected — redirect to a per-iteration
# log file under .bug-hunt/, then tail the file. NEVER pipe hunt.sh stdout into tail
# (see §4b for why).
LOGFILE=".bug-hunt/phase${P}-iter${ITER}.log"
bash "$SKILL_DIR/scripts/hunt.sh" \
  --phase <P> \
  --engine <ENGINE> \
  --model <M> \
  --journal-file .bug-hunt/journal.md \
  [--dry-run] > "$LOGFILE" 2>&1
tail -120 "$LOGFILE"
```

The script reads `--journal-file` and prepends its contents to the engine prompt.

## Important Rules

1. **Engine-appropriate sandbox** — codex: `--sandbox workspace-write`; gemini: `--sandbox`; claude: `isolation: worktree`
2. **Always include AGENTS.md rules** — prepend to every engine prompt
3. **Default engine is codex** — override with `--engine`
4. **Source env secrets** — run `source ~/.env.secrets 2>/dev/null` before codex/gemini
5. **Pre-flight concurrency gate before dispatch** — `hunt.sh` blocks if active host-wide `codex exec` + `gemini -p` jobs are already at the cap (default `2`; override with `SWARM_MAX_CONCURRENT` or `--max-concurrent N`). Refusals happen before any phase dispatch, so dry-run reflects real-run behavior.
6. **Per-iteration engine timeout** — shared codex wrapper defaults to `900s`, gemini wrapper defaults to `480s` per iteration. Override with `CODEX_ITER_TIMEOUT` / `GEMINI_ITER_TIMEOUT`, or wrapper flag `--timeout N` when calling the engine script directly.
7. **Timeout 10 minutes per orchestrator iteration** — engine deep analysis is slow
8. **Report concisely** — show iteration count, files changed, not raw logs
9. **Never skip quality gates** — remind user to run UBS after completion
10. **Don't get stuck in communication purgatory** — check mail between phases, not iterations. Be proactive; inform, don't ask.
11. **Respect file reservations** — if another agent has reserved files, tell the engine to skip them
12. **Announce, don't ask** — send "I'm starting phase N" messages, don't wait for replies
13. **Journal is the memory** — every iteration must post findings to the hunt thread. Skipping this breaks the accumulation loop.
14. **Prior hunts inform current hunts** — always check `fetch_topic("bug-hunt")` at startup for recurring patterns
15. **No parallel sessions on same repo** — running multiple bug-hunt sessions on the same checkout causes OOM kills and journal pollution. Use separate worktrees or run sequentially. `hunt.sh` now hard-refuses dispatch at the shared concurrency cap instead of only warning.
16. **Journal hard cap is 2KB** — both the `--no-mail` journal file and `summarize_thread` output must be trimmed to 2KB before passing to the engine. Priority: unexplored areas > patterns > recent results.
17. **Feature creep = revert** — engines sometimes add features (new deps, CI workflows, config files) instead of fixing bugs. `hunt.sh` flags new non-test files after each iteration. Review these and `git revert` any feature-creep commits immediately.
18. **Agent Mail is parent-only** — only the orchestrating Claude Code session registers with Agent Mail. Engine sub-processes have no MCP access and must not be told to register or send messages.
19. **Git safety is NON-NEGOTIABLE** — every engine prompt must carry the git-safety block. Engines must never `git commit --amend`, `git revert`, `git reset`, `git rebase`, `git cherry-pick`, or force-push. Fixes go in NEW commits on top of HEAD. Parallel agents may be committing to the same branch from other worktrees — treat every existing commit as potentially another-agent-authored and immutable. Before interpreting unexpected commits as scope violations, check `git reflog` and `fetch_inbox` — this rule exists because a prior swarm-build incident (2026-04-17) had a codex iteration amend a parallel agent's commit, then revert the amended commit as "out of scope," erasing legitimate work.
20. **Never trust the engine's "tests pass" claim** — the orchestrator re-runs the project's full quality gates after every iteration (every phase) and compares against `$TEST_BASELINE`. Pass-to-fail deltas are regressions even if framed as pre-existing; fail-to-pass deltas are the goal; tests the engine silently skipped/deleted are a judgment call that leans suspicious. Falsify any "pre-existing failure" claim via `git worktree add $PRISTINE $start_sha` and re-run the specific test there — `git stash` is the wrong tool because it can't capture the engine's committed changes. This rule exists because test fixtures can leak state across files (autouse fixtures mutating `os.environ` bypass `monkeypatch`), and those failures look "unrelated" to the engine that caused them.
21. **Engine dispatch redirects to a log file, never pipes to `tail`** — every `bash hunt.sh ...` call must use `> "$LOGFILE" 2>&1` (with `$LOGFILE` under `.bug-hunt/`) followed by a separate `tail -120 "$LOGFILE"` read. The `producer-pipe-to-tail` pipeline blocks the engine wrapper once stdout exceeds the OS pipe buffer (~16KB on macOS) if the consumer ever stalls or gets orphaned by the harness — observed 2026-04-26 in a swarm-build session (codex.sh wrapper alive with `lsof` showing fd 1 → `PIPE 16384`, no codex child running, tail never produced output). File redirection has no buffer cap and preserves full output for post-mortem.
22. **Agent Mail retry policy + inbox rate-limit** — `mcp-agent-mail` sometimes hits transient resource exhaustion under sustained hunt/swarm load. The MCP server returns one of these two patterns inside the tool result while `health_check` still reports ok:
    - `Database connection pool exhausted`
    - `Too many open files. Freed <N> cached repos`

    `mcp-agent-mail` is invoked as JSON-RPC tool calls, **not** a CLI — so this is an orchestrator-side conversational policy, not a shell pipeline. When you see either pattern in a `send_message` / `fetch_inbox` / `file_reservation_paths` result: wait 5s and retry the same tool call; if still transient, wait 15s and retry; if still transient, wait 45s and retry; after 3 retries with the same pattern, treat Agent Mail as unavailable and fall back to the CLAUDE.md "Agent Mail unavailable: proceed normally" rule for the rest of the session.

    Non-transient errors (schema, auth, 4xx) propagate immediately — don't retry. Reference implementation: `skills/shared/retry-mcp.sh` + `tests/test_mcp_retry.sh` (helper wraps shell commands; the policy it encodes is what the orchestrator follows in conversation).

    Additionally, **check the inbox at most every 5 iterations** (between phases, never every iteration) — per-iteration polling amplifies server load and is what trips pool/fd exhaustion in the first place. Root-cause fix tracked in `mcp-agent-mail` repo (bd-9nd); this rule is the client-side mitigation (bd-j1x).
23. **If the project's AGENTS.md tells codex to run `ubs`, scope it to specific files, not `ubs .`** — whole-project scans on non-trivial repos exceed codex's per-shell-command timeout and read as a hang from inside the sandbox. Pass an explicit file list (e.g. the paths the agent just modified in this iteration). **Gotcha:** `ubs $(some-git-command)` falls back to scanning PROJECT_DIR when the substitution is empty — the exact failure mode this rule prevents. Either guard with `[[ -n "$FILES" ]] && ubs $FILES`, or combine working-tree + iteration-commit diffs like `hunt.sh` does (`git diff --name-only` ∪ `git diff --name-only ${start_sha}..HEAD`). (Repro 2026-05-16 confirmed `ubs` itself works fine in `--sandbox workspace-write`; the apparent hangs are scan-scope/timeout, not sandbox.) `hunt.sh` also runs `prewarm_ubs.sh` before dispatch so the first iteration doesn't pay module-download cost inside the sandbox.
