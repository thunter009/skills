---
name: autoreview
description: "Run a structured code review (Codex default, Claude optional) as a closeout check on a local or PR branch before commit or ship."
category: code
related-skills:
- codex
---

# Auto Review

Run the bundled structured review helper as a closeout check. This is code review, not Guardian `auto_review` approval routing.

Codex review is the default when no engine is set. It usually delivers the best review results and should remain the normal final closeout engine.

Use when:

- user asks for Codex review / Claude review / autoreview / second-model review
- after non-trivial code edits, before final/commit/ship
- reviewing a local branch or PR branch after fixes

## Contract

- Treat review output as advisory. Never blindly apply it.
- Verify every finding by reading the real code path and adjacent files.
- Read dependency docs/source/types when the finding depends on external behavior.
- Reject unrealistic edge cases, speculative risks, broad rewrites, and fixes that over-complicate the codebase.
- Prefer small fixes at the right ownership boundary; no refactor unless it clearly improves the bug class.
- When an accepted finding shows a bug class or repeated pattern, inspect the current PR scope for sibling instances before fixing.
- Fix the scoped bug class at once when practical; stop at touched surfaces, owner boundaries, and clear follow-up territory.
- Run one substantive review, verifying its findings against real code. Fix accepted defects and check the affected behavior; do not chase a cosmetically clean verdict or repeat the full review for informational observations. Preserve unresolved-HIGH merge gates and explicitly record any remaining accepted findings.
- **Contradiction rule:** when a round's finding contradicts an earlier round's finding on the same claim — including a finding that would reverse a fix you already applied — do not apply either side on reviewer authority alone. Pin the claim to a checkable primary source first (tool `--help` text, official docs, a reproduction command you run yourself); the reviewer asserting it "is documented" is not a source until you verify the citation. If no such source settles it, record the claim as unverified and shape the code/doc to be safe under both readings. (Origin: a 2026-07 review loop flip-flopped 4 rounds on whether gh-stack stack/PR numbers can collide; it converged only when a round cited `gh stack link --help` verbatim — "stack and PR numbers never overlap" — and the orchestrator verified it.)
- **Carry rejections forward:** when you reject a finding on primary evidence, record it in a rejected-findings file and pass that file to every later round with `--rejected-findings` (see Multi-Round Reviews). A settled claim then needs new evidence before it comes back. (Origin: PR 380, 2026-09-14: rounds 6 and 7 each re-raised a false P1, and each cost a full verify cycle.)
- **UNVERIFIED findings:** the helper moves a finding to `unverified_findings` when its `quoted_code` is not within 10 lines of the cited line or in that file's diff. It prints the finding as `[UNVERIFIED P1]` and does not count it toward the exit code. Read the cited location once. If the claim holds on the real code, treat it as a normal finding; if not, add it to the rejected-findings file. Do not rerun the review only to clear it.
- After a fix, rerun affected tests and review the fix against the accepted finding. Use a focused helper recheck for materially changed behavior or unresolved risk; repeat the full review only when scope or risk expands. If publishing evidence for a new head, the recheck must cover the intervening changes and clearly state its scope; never relabel an old result as current.
- For security-audit suppression changes, verify accepted findings remain auditable: suppressed findings stay in structured output, active output keeps an unsuppressible suppression notice, and aggregate findings cannot hide unrelated active risk.
- Never switch or override the requested review engine/model. If the review hits model capacity, retry the same command a few times with the same engine/model.
- If the helper stops with `codex engine failed: codex is not logged in, or its login expired`, run `codex logout`, then `codex login`, then rerun the same command. A retry without a new login fails the same way.
- Be patient with large bundles. Structured review can take up to 30 minutes while the model call is active, especially with Codex tools or web search.
- Treat heartbeat lines like `review still running: ... elapsed=... pid=...` as healthy progress, not a hang. Let the helper continue while heartbeats are advancing. Pass `--stream-engine-output` when live engine text is useful; Codex and Claude filter tool/file chatter, other engines pass raw output through.
- Do not kill a review just because it has been quiet for 2-5 minutes, or because it is still running under the 30-minute window. Inspect the process only after missing multiple expected heartbeats, after 30 minutes, or after an obviously failed subprocess; prefer letting the same helper command finish.
- Tools are useful in review mode. The helper allows read-only inspection tools and web search by default so reviewers can check dependency contracts, upstream docs, and current behavior.
- Security perspective is always included, but it should not cripple legitimate functionality. Report security findings only when the change creates a concrete, actionable risk or removes an important safety check.
- For regression provenance, keep roles separate: blamed code author, blamed PR author, PR merger/committer, current PR author, and PR/date. If no blamed PR is traceable, use the blamed commit as the provenance: commit SHA, date, and author username. Do not guess a merger or frame missing PR metadata as a separate finding.
- If the blamed PR was merged by `clawsweeper[bot]` or another automation, identify the human trigger when practical. Check timeline/comments first; if rate-limited, use gitcrawl/cache or public PR HTML. Look for maintainer commands such as `@clawsweeper automerge`, `/landpr`, or labels/status comments that armed automerge. Report `automerge triggered by @login`; if not found, say trigger unknown.
- Do not invoke built-in `codex review`, nested reviewers, or reviewer panels from inside the review. The helper builds one bundle, calls one selected engine, validates one structured result, and stops.
- Stop as soon as the helper exits 0 with no accepted/actionable findings. Do not run an extra review just to get a nicer "clean" line, a second opinion, or clearer closeout wording.
- Treat the helper's successful exit plus absence of actionable findings as the clean review result, even if the underlying Codex CLI output is terse.
- Multi-reviewer panels are opt-in only. Use them when explicitly requested or when risk justifies the extra spend; the main agent still verifies every accepted finding before fixing.
- If rejecting a finding as intentional/not worth fixing, add a brief inline code comment only when it explains a real invariant or ownership decision that future reviewers should know.
- If `gh`/Gitcrawl reports `database disk image is malformed`, run `gitcrawl doctor --json` once to let the portable cache repair before retrying review; do not bypass the shim unless repair fails and freshness requires live GitHub.
- If Gitcrawl reports a portable manifest mismatch, source/runtime DB health error, or stale portable-store checkout, run `gitcrawl doctor --json` and inspect `source_db_health`, `runtime_db_health`, and `portable_store_status` before falling back to live GitHub.
- Do not push just to review. Push only when the user requested push/ship/PR update.

## Pick Target

Dirty local work:

```bash
~/.claude/skills/autoreview/scripts/autoreview --mode local
```

Use this only when the patch is actually unstaged/staged/untracked in the
current checkout. `--mode uncommitted` is accepted as an alias for `--mode local`.
For committed, pushed, or PR work, point the helper at the commit
or branch diff instead; do not force dirty modes just
because the helper docs mention dirty work first. A clean local review
only proves there is no local patch.

Branch/PR work:

```bash
~/.claude/skills/autoreview/scripts/autoreview --mode branch --base origin/main
```

Optional review context is first-class:

```bash
~/.claude/skills/autoreview/scripts/autoreview --mode branch --base origin/main --prompt-file /tmp/review-notes.md --dataset /tmp/evidence.json
```

If an open PR exists, use its actual base:

```bash
base=$(gh pr view --json baseRefName --jq .baseRefName)
~/.claude/skills/autoreview/scripts/autoreview --mode branch --base "origin/$base"
```

Committed single change:

```bash
~/.claude/skills/autoreview/scripts/autoreview --mode commit --commit HEAD
```

Use commit review for already-landed or already-pushed work on `main`. Reviewing
clean `main` against `origin/main` is usually an empty diff after push. For a
small stack, review each commit explicitly or review the branch before merging
with `--base`.

## Multi-Round Reviews

After each round, append every finding you rejected to one JSON file. Pass that file to every later round:

```json
[
  {
    "claim": "Prompt reads 'Run downloads-triage skill on'",
    "evidence": "grep -n shows line 42 reads 'Run the downloads-triage skill on'",
    "location": "skills/downloads-triage/SKILL.md:42"
  }
]
```

```bash
~/.claude/skills/autoreview/scripts/autoreview --mode branch --base origin/dev --rejected-findings /tmp/rejected.json
```

- Each entry needs exactly `claim`, `evidence`, and `location` (`file:line`). The helper refuses any other shape before it starts the engine.
- `evidence` must be primary: a command you ran and its output, a test result, or a verbatim doc citation. Do not write "the reviewer was wrong".
- The prompt tells the reviewer not to re-raise a listed claim without new evidence. This is an instruction to the model. The helper does not filter the output, so verify a re-raised claim like any other finding.

## Parallel Closeout

Format first if formatting can change line locations. Then it is OK to run tests and review in parallel:

```bash
~/.claude/skills/autoreview/scripts/autoreview --parallel-tests "<focused test command>"
```

On Windows, the default `--parallel-tests` shell preserves the platform `cmd.exe`
semantics used by Python `shell=True`. Use `--parallel-tests-shell powershell`
or `--parallel-tests-shell pwsh` when the focused test command is PowerShell-specific.

Tradeoff: tests may force code changes that stale the review. If tests or review lead to code edits, rerun the affected tests and rerun review until no accepted/actionable findings remain. Once that rerun exits cleanly, stop; do not spend another long review cycle on redundant confirmation.

## Long runs under an agent harness

A review can run for 5-30 minutes. Agent harnesses stop long commands before that:

- Claude Code killed a foreground run at 2 minutes (exit 143) on 2026-09-02. It also killed `run_in_background: true` at 2 minutes (a private data repo, 14 review rounds).
- Claude Code on 2026-10-28 moves a foreground command to the background at 2 minutes. It stops that command at 30 minutes.

Run the helper with `--detach`. It starts the review in a new session, prints the pid and log path, and exits 0 at once:

```bash
~/.claude/skills/autoreview/scripts/autoreview --detach --log /tmp/autoreview.log --mode branch --base origin/dev --json-output /tmp/review.json
# autoreview detached: pid=72333 log=/tmp/autoreview.log
# done when the log's last line is AUTOREVIEW_EXIT=<status> (0 = clean)
```

- The helper calls `setsid(2)` through Python. This works on macOS, which has no `setsid` command. A kill of the caller's process group does not reach the review.
- The log holds all helper output, heartbeats included. Its last line is `AUTOREVIEW_EXIT=<status>`: `0` = clean, `1` = findings or a failure. Read the log to tell which.
- `--log` is optional. The default is a new temp file. The helper truncates the log at launch, so a reused path holds no stale marker. It refuses a log inside the repository, because a local review would bundle that file.
- Read findings from `--json-output`, not from the log.

Wait in one background watch, not in repeated foreground polls. In Claude Code, use `run_in_background: true` or Monitor:

```bash
pid=72333; while kill -0 "$pid" 2>/dev/null; do sleep 15; done; tail -n 40 /tmp/autoreview.log
```

The loop also ends when the review dies. A log without a final `AUTOREVIEW_EXIT=` line means that the review died. If the harness stops the watch, the review continues; start a new watch.

Without `--detach` (an older deployed helper), detach by hand. Keep the single quotes, so that `$?` expands in the inner shell:

```bash
LOG=/tmp/autoreview.log nohup bash -c '~/.claude/skills/autoreview/scripts/autoreview --mode branch --base origin/dev >"$LOG" 2>&1; echo "AUTOREVIEW_EXIT=$?" >>"$LOG"' </dev/null >/dev/null 2>&1 &
```

- Do not put `setsid` in front on macOS. The command does not exist, `>/dev/null 2>&1` hides the error, and no review starts.
- This run stays in the caller's process group. On Linux, `setsid -f bash -c '…'` moves it out. `--detach` does this on both systems.

## Review Panels

Run multiple reviewers against one frozen bundle:

```bash
~/.claude/skills/autoreview/scripts/autoreview --reviewers codex,claude
```

`--panel` is shorthand for Codex plus Claude unless `--engine` changes the first reviewer:

```bash
~/.claude/skills/autoreview/scripts/autoreview --panel
```

Set reviewer models and thinking/effort explicitly:

```bash
~/.claude/skills/autoreview/scripts/autoreview --reviewers codex,claude --model codex=gpt-5.1 --thinking codex=high --model claude=sonnet --thinking claude=max
```

Inline syntax is also supported:

```bash
~/.claude/skills/autoreview/scripts/autoreview --reviewers codex:gpt-5.1:high,claude:sonnet:max
```

Codex maps thinking to `model_reasoning_effort` and accepts `low`, `medium`,
`high`, or `xhigh`. Claude maps thinking to `--effort` and also accepts `max`.
Engines without a real thinking knob reject `--thinking`.

## Context Efficiency

Run the helper directly so target selection, engine choice, structured validation, and exit status all stay in one path. If output is noisy, summarize the completed helper output after it returns; do not ask another agent or reviewer to rerun the review.

## Helper

The helper is deployed at `~/.claude/skills/autoreview/scripts/autoreview` and is
self-locating (it finds its sibling scripts via its own path), so invoke it with
that absolute path when reviewing code in **any** project — a bare relative
`skills/autoreview/...` path only resolves when the cwd is the agent-skills repo:

```bash
~/.claude/skills/autoreview/scripts/autoreview --help
```

When working inside the agent-skills repo itself (editing or smoke-testing the
skill), the repo-source path also works:

```bash
skills/autoreview/scripts/autoreview --help
```

On native Windows, invoke the extensionless Python helper through Python:

```powershell
python %USERPROFILE%\.claude\skills\autoreview\scripts\autoreview --help
```

The smoke harness has thin shell wrappers over a shared Python implementation
(run from the agent-skills repo checkout):

```bash
skills/autoreview/scripts/test-review-harness --fixture benign --engine codex
```

```powershell
skills\autoreview\scripts\test-review-harness.ps1 -Fixture benign -Engine codex
```

The helper:

- chooses dirty local changes first
- accepts `--mode uncommitted` as an alias for `--mode local`
- otherwise uses current PR base if `gh pr view` works
- otherwise uses `origin/main` for non-main branches
- supports `--engine codex`, `claude`, `droid`, and `copilot`; default is `AUTOREVIEW_ENGINE` or `codex`; Codex should remain the default when nothing is set
- resolves bare `git`, `gh`, reviewer, and PowerShell shell commands from absolute `PATH` entries only, never from the reviewed checkout; explicit relative `--*-bin` paths are resolved from the reviewed repository root
- use `--mode commit --commit <ref>` for already-committed work, especially clean `main` after landing
- should be left in `--mode auto` or forced to `--mode branch` for PR/branch work; do not force `--mode local` after committing
- writes only to stdout unless `--output`, `--json-output`, or live streamed engine stderr is set
- supports `--dry-run`, `--parallel-tests`, `--parallel-tests-shell`, `--prompt`, `--prompt-file`, `--dataset`, `--rejected-findings`, `--no-tools`, `--no-web-search`, and commit refs
- asks for each finding's `quoted_code`, checks it against the cited location and the diff (whitespace-insensitive, `...` skips text), and moves a finding whose quote is absent to `unverified_findings`
- stops Codex on its first login error line (expired, revoked, or missing login) and prints the `codex logout` / `codex login` fix, instead of waiting through minutes of retries
- supports `--stream-engine-output` or `AUTOREVIEW_STREAM_ENGINE_OUTPUT=1` for live engine text while preserving structured validation; Codex and Claude hide tool/file event details, emit compact activity summaries, and report usage at turn completion
- supports opt-in review panels with `--panel` / `--reviewers`, plus per-engine `--model` and `--thinking`
- supports `--detach` and `--log` for a review that must outlive the calling command (see Long runs under an agent harness)
- allows read-only tools and web search by default where the selected CLI supports them; forbids nested review in the prompt; Codex is run through `codex exec` with read-only sandbox and structured output
- prints `review still running: <engine> elapsed=<seconds>s pid=<pid>` to stderr at long-running intervals while waiting for the selected review engine, unless streamed output or compact Codex activity has been visible recently
- prints `autoreview clean: no accepted/actionable findings reported` when the selected review command exits 0
- exits nonzero when accepted/actionable findings are present

## Before self-merging: post the verdict to the PR

A local review is invisible to everyone but you. The squash drain's gate
(`squash-pr/scripts/review-evidence.sh`) and any later audit read a PR with no review body at
its head as **UNREVIEWED** — agent-skills #414 (2026-09-17) was codex-reviewed here, three
findings fixed, self-merged, and left zero review artifacts on GitHub. So when the PR you are
about to merge yourself was reviewed only by this skill, post the final run as a COMMENT review
first:

```bash
~/.claude/skills/autoreview/scripts/autoreview --mode branch --base origin/dev --json-output /tmp/review.json
~/.claude/skills/autoreview/scripts/post-review-evidence.sh <pr> --from /tmp/review.json --rounds <N>
gh pr merge <pr> --squash --delete-branch --match-head-commit "$(gh pr view <pr> --json headRefOid -q .headRefOid)"
```

- Use the **final** helper run's JSON (the clean one, or the one whose remaining findings you
  consciously rejected). `--rounds` is how many review/fix passes it took; it goes in the body.
- The script pins the review to the head SHA it was given and refuses if the head moved — a
  review of older code is not evidence about the code being merged. Re-run the helper, then post.
- Event is always **COMMENT**. It never approves, never requests changes, never merges. The
  merge-authority rule (CI green + review clean, no unresolved HIGH) is unchanged; this only
  makes the review *visible* where the gate looks.
- Skip it when the PR already carries a substantive review at head from the PR review sweep or
  a human — check with `squash-pr/scripts/review-evidence.sh <pr>` (exit 0 = already covered).

## Final Report

Include:

- review command used
- tests/proof run
- findings accepted/rejected, briefly why
- the clean review result from the final helper/review run, or why a remaining finding was consciously rejected

Do not run another review solely to improve the final report wording. If the final helper run exited 0 and produced no accepted/actionable findings, report that exact run as clean.
