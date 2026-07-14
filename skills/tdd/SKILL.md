---
name: tdd
description: Implement changes with strict red-green-refactor discipline.
when-to-use:
- tdd, test-driven, red green refactor
- When the user wants test-first work
permissions:
- read
- write
- bash
category: testing
---

# Test-Driven Development

Implement **$ARGUMENTS** using strict test-first workflow.

## Test Quality Philosophy

**Tests verify behavior through public interfaces, not implementation details.** Code can change entirely; tests shouldn't. A good test reads like a specification ("user can checkout with valid cart") and survives internal refactors. Warning sign of a bad test: it breaks when you refactor but behavior hasn't changed.

Red flags:
- Mocking internal collaborators or asserting on call counts/order
- Testing private functions directly
- Verifying through external means (querying the DB directly) instead of through the interface — prefer `create then retrieve via the API` over `create then SELECT`

**Mock at system boundaries only** (external APIs, time/randomness, sometimes DB/filesystem — prefer a test DB). Never mock your own modules. If a boundary is hard to mock, that's an interface problem: inject dependencies instead of constructing them internally, and prefer SDK-style interfaces (one function per operation) over generic fetchers so each mock returns one shape.

**Vertical slices, not horizontal.** Do NOT write all tests first, then all implementation — bulk-written tests test *imagined* behavior and the *shape* of things, and go insensitive to real changes. One test → one implementation → repeat; each test responds to what the previous cycle taught you.

## Step 0: Detect Test Infrastructure

```bash
# Find test runner and config
ls pytest.ini pyproject.toml setup.cfg jest.config* vitest.config* Cargo.toml 2>/dev/null
# Find existing tests for context
find . -name 'test_*' -o -name '*_test.*' -o -name '*.test.*' | head -20
```

Note the runner, config location, and any flags the project uses. **Gotcha:** `--fail-no-tests` is not supported by all pytest versions — check before using.

## Step 1: Assess — Does This Code Have Tests?

Check if the target module already has test coverage:

```bash
# Check for existing tests
find . -name 'test_*' -path '*<module_name>*' 2>/dev/null
```

- **Has tests**: Standard TDD — write next failing test, implement, refactor
- **No tests**: Write a characterization test first (captures current behavior), then TDD for new behavior

## Step 2: Red-Green-Refactor Cycle

One behavior at a time:

### RED — Write one failing test

```bash
# Run the test — it MUST fail
pytest tests/test_feature.py::test_new_behavior -x -v
```

Verify it fails for the **right reason** (missing function, wrong return value — not import error or syntax error).

### GREEN — Minimal implementation

Write the minimum code to make the test pass. No extra features, no "while I'm here" additions.

```bash
# Verify it passes
pytest tests/test_feature.py::test_new_behavior -x -v
```

### REFACTOR — Improve design

Clean up while keeping tests green. Run the full relevant test suite:

```bash
pytest tests/test_feature.py -v
```

### Commit the cycle

Group related red-green-refactor cycles into one commit when they address a single behavior. Don't commit per-cycle — commit at logical boundaries.

```bash
git add src/feature.py tests/test_feature.py
git commit -m "feat: add <behavior> with test"
```

## Step 3: Repeat

Move to the next behavior. Continue until all behaviors specified in $ARGUMENTS are covered.

## Legacy Code Workflow

When modifying untested existing code:

1. **Characterization test** — capture current behavior as a safety net
2. **Refactor for testability** — extract functions, inject dependencies (smallest changes possible)
3. **TDD for new behavior** — follow the cycle above

Never refactor without a safety net test first.

## Rules

- One test at a time. No bulk implementation.
- Minimal implementation — if the test doesn't demand it, don't build it
- Tests go in the same commit as their implementation
- Never commit failing tests
- Run `ubs` on changed files before final commit
