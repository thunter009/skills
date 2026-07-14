---
name: simplify
description: Review recent code changes for reuse, quality, and unnecessary complexity.
when-to-use:
- simplify, clean up my changes, review my diff
- After feature work before commit
permissions:
- read
- write
- bash
category: code
---

# /simplify — Post-Change Quality Review

Quick review of what changed in the current branch/session. Did you leave any mess?

**This is NOT /refactor** (intentional restructuring) or /deep-review (adversarial audit). This is a lightweight "did I leave any mess?" pass after feature work.

## Step 1: Detect What Changed

```bash
git diff --name-only HEAD~5 2>/dev/null || git diff --name-only main...HEAD
```

If on a feature branch, scope to changes since branching. If on main, scope to the last few commits.

## Step 2: Scan for Common Post-Change Issues

For each changed file, check:

### Stale references
- Constants/configs that look valid but are wrong (hardcoded IPs, old paths, help text defaults)
- Import paths that reference renamed/moved modules
- Dead code from prior refactors (no-op branches, unreachable conditions)
- Functions only called from deleted code

### Duplication
- Did the new code duplicate something that already exists?
- Could a shared helper replace 2+ similar blocks?
- Repeated string constants that should be centralized

### Unnecessary complexity
- Over-abstracted patterns for one-time operations
- Feature flags or backwards-compatibility shims for removed code
- Error handling for scenarios that can't happen

### Run ubs on changed files

```bash
ubs $(git diff --name-only HEAD~5 2>/dev/null || git diff --name-only main...HEAD)
```

Fix any findings before committing.

## Step 3: Compare Outputs (if applicable)

For data-touching changes, verify outputs match expectations:
- Schema/dtype: compare parquet schemas, JSON shapes, API responses
- Row counts: matching counts don't prove correctness — check dtypes too
- Config consumers: does anything read the old key/path/value?

## Step 4: Fix and Commit

Fix issues found. Split fixes into atomic commits — one logical change per commit.

## Rules

- Don't over-scope. This is a 5-minute pass, not a full refactor.
- Don't add features, refactor unrelated code, or "improve" things that aren't broken.
- If you find something that needs a bigger fix, note it as a follow-up — don't do it now.
- Dedup over test coverage: if code is duplicated, consolidate rather than writing tests for both copies.
