---
name: deep-review
description: Run adversarial, flow-tracing code review and fix real issues.
when-to-use:
- deep review, thorough review, adversarial review
- When normal review is too shallow
user_invocable: true
category: code
---

Run a deep review cycle on this codebase. Trace high-risk execution flows and fix real bugs.

**Scope:** $ARGUMENTS (if empty, auto-detect: ingestion pipelines, auth flows, data processing, API handlers)

**Pre-survey — sister-session WIP detection (always run first):**
In multi-tenant repos (shared cwd, agent swarms), origin-divergence checks alone miss local untracked drafts that may already cover your planned scope. Skipping this step risks duplicating in-flight audit findings, spec drafts, or refactor work.
1. `git status -s` — flag tracked-file modifications (likely sister-session WIP).
2. `ls -lat docs/ docs/architecture/ docs/ops/ docs/product/ 2>/dev/null | head -30` — surface recently-touched audit/spec drafts.
3. Read any untracked files matching `*audit*`, `*findings*`, `*spec*`, `data-warehouse.md`, `*charter*` under `docs/` — sister sessions routinely land these as untracked output.
4. If a sister-WIP doc covers part of your planned scope: **reduce to net-new items**, reference the sister doc in your final output, do not compete.

**Round type A — Targeted Flow Tracing:**
Pick 3-5 high-risk execution flows (not random files). Trace each through imports and call chains end-to-end. Check for:
- Silent data corruption (`list(string)` char-splitting, `hash()` salted per-process, truthy checks hiding zero)
- Stale references (renamed files still referenced in configs/beads/docs, wrong paths, hardcoded IPs after migration)
- Datetime issues (`utcnow()` deprecation, naive vs aware, timezone mismatches)
- Framework version mismatches (docs claim Express but code uses bare http, etc.)

**Round type B — Bead/Ticket Accuracy Audit:**
If the project uses beads or Linear, audit open tickets against actual codebase state:
- Do "missing test" claims hold up? (check if tests actually exist)
- Do file references match actual filenames?
- Are exit conditions executable? (no fake commands, no prose-only steps)
- Flag false dependency chains that block parallelism

**Protocol:**
0. Run the **Pre-survey** above. Re-scope if a sister session is already covering part of the work.
1. Run `ubs` on the scope (changed files or target directory) — fix findings first
2. Run Round A. Report findings. Fix bugs.
3. Run Round B (if beads/Linear present). Report findings. Fix descriptions.
4. Split fixes into atomic commits. Run full test suite after each.
5. If Round A found issues, do one more pass. Stop after a clean pass.

**Subagent triage:** If using parallel Explore agents, triage ALL findings before acting. Verify each by reading source — agents flag intentional patterns as bugs (~20-30% false positive rate). Discard false alarms, note "Left as-is" with reason.

**Common bug checklist:**
- [ ] Persistent hash stability (PEP 456 — `hash()` is salted per-process)
- [ ] Datetime tz-awareness (no `utcnow()`, use `datetime.now(UTC)`)
- [ ] Truthy vs None checks (0 and "" are falsy)
- [ ] Stale path/file references across configs
- [ ] Exit condition executability (no `playwright-cli` fake commands)
- [ ] ERE/BRE regex mode confusion in grep patterns

Report at end: total rounds, files reviewed, bugs found and fixed, false positives discarded, final test suite status.
