---
name: refactor
description: Refactor code with scoped cleanup and safer structure changes.
when-to-use:
- refactor, clean up code, improve structure
- When code needs structural change
permissions:
- read
- write
- bash
category: code
related-skills:
- autoreview
---

# Systematic Code Refactoring

Focus on improving code design while keeping tests green.

**Target:** $ARGUMENTS

## Safety Checks (Before Any Changes)

```bash
# Verify you're in the right repo and on the right branch
git remote -v | head -1
git branch --show-current
pwd
```

Wrong-repo and wrong-branch commits are a real hazard during refactoring. Verify CWD matches the intended project.

## Scope Detection

If no arguments provided:
- **On feature branch**: Assess changes since branching from main
- **On main branch**: Ask user what they'd like refactored

If arguments provided:
- **File path**: Refactor specific file (e.g., "src/auth.js")
- **Module/area**: Refactor specific functionality (e.g., "authentication module")
- **PR review findings**: Triage review comments, accept/reject each, implement accepted ones

## Common Refactoring Types

| Type | What to watch for |
|------|-------------------|
| **Extract/rename** | Import path changes break downstream silently |
| **Dependency removal** | Identify what the dep provides, inline or replace, verify identical behavior, update lockfiles |
| **Config consolidation** | S3 paths, env vars, install scripts — centralize but verify all consumers |
| **Cross-repo consistency** | Mirror changes across sibling repos, verify each independently |
| **Dead code removal** | Constants/configs that look alive but are stale (wrong IPs, outdated lists) |

## Refactoring Workflow

1. **Assess current code** — read, understand scope and boundaries, run tests to capture current behavior

2. **Quick risk check** — is this safe to change right now?
   - Well-tested: proceed directly
   - Some coverage: proceed carefully, compare outputs
   - No coverage: write characterization tests first

3. **Make incremental changes** — one improvement at a time, run tests after each

4. **Validate based on risk**:
   - **Low risk**: unit tests pass
   - **Medium risk**: compare output artifacts (parquet schemas, JSON shapes, API responses) before vs after
   - **High risk**: full end-to-end pipeline run with output comparison

5. **Split into atomic commits** — each commit = one logical change, independently valid:
   ```bash
   git add -p  # interactive staging for clean splits
   ```
   Separate concerns: code vs docs vs metadata vs config. A module + its test file = same commit. This is the most common refactoring operation — don't skip it.

## Silent Breakage Warnings

Refactoring can break things without errors:

- **Asset key renames** (Dagster, etc.) — `@dlt_assets` generates keys from source/resource names. Renaming changes all keys, breaking the DAG lineage silently
- **Import path changes** — downstream code with stale imports may fail at runtime, not import time
- **Config key renames** — consumers reading the old key get None/default silently
- **Dtype coercion** — schema changes hidden behind matching row counts
- **Constants that look valid** — `PROXY_LIST` with 0/20 correct IPs, stale LAN addresses after migration
- **`rm(list=ls())` in R** — drops sourced helpers; whitelist must include new functions

After refactoring, explicitly verify outputs match pre-refactor state where possible.

## Code Smell Checklist

- Long functions (>20 lines) with multiple responsibilities
- Deep nesting (>3 levels)
- Magic numbers/strings without named constants
- Feature envy (accessing other objects' data excessively)
- Shotgun surgery (small changes touching many files)
- Dead code: unused functions, unreferenced config options, stale constants
- Duplicated validation logic, repeated string constants

## Goal Mode — autonomous refactor sprint (idle-quota burner)

For spending idle/banked quota on architecture debt: a `/goal`-driven loop that refactors until the architecture is satisfying, live-testing and committing as it goes (steipete's pattern). Paste-ready:

```
/goal refactor <scope> until you are happy with the architecture. Ensure you
live-test after each significant step and autoreview + commit each step.
Track progress in /tmp/refactor-<project>.md (what changed, why, test
evidence, what's next). Live test = full verification by whatever it takes:
run the suite, run the app, browser/computer use, real keys from the
environment. Stop only at the project's stop-rule boundaries
(schema/contract changes, product semantics, spend).
```

**Hard preconditions before launching:**
1. **Private worktree, always, in multi-tenant checkouts.** An unattended refactor loop sharing HEAD with sister sessions is the canonical collision incident. `git worktree add .ntm/worktrees/refactor-<date> -b refactor/<scope> origin/<int-branch>` and run the goal there.
2. **Discuss direction first on bigger projects** — agree the target architecture in one shaping exchange before letting it run; small repos can go straight in.
3. **Autoreview on** — every significant step gets `/autoreview` before its commit; you want to find bugs during the refactor, not after landing.
4. Behavior-preservation rules above still bind: tests green throughout, outputs verified against pre-refactor state, atomic commits.
5. Endpoint per project conventions: branch + PR for review (refactors are wide-blast-radius — conditioned self-merge generally should NOT apply; state the operator gate in the goal if so).

**Overnight/async use:** wire through cron, `/schedule`, or a scheduled cloud agent; the `/tmp/refactor-<project>.md` progress file is the morning-read artifact. Pilot on a low-blast-radius repo (e.g. the skills repo itself) before pointing at production pipelines.

## Principles

- Keep tests green throughout
- Make small, focused improvements
- Split into atomic commits with `git add -p`
- Focus on code you recently wrote or are actively changing
- Test behavior remains unchanged — verify outputs, not just test pass/fail
- When refactoring from PR review findings, verify each finding against actual code before acting (~25% of automated review findings are false positives)
