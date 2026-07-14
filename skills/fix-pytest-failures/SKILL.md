---
name: fix-pytest-failures
description: Diagnose and fix failing pytest tests from names or stack traces.
when-to-use:
- fix pytest failures, failing tests, pytest error
- When given a traceback or failing test list
permissions:
- read
- write
- bash
category: testing
---

# Fix Pytest Failures

You are an expert Python developer and test engineer. You will be given either:

- a list of failing pytest tests (by node id, file::class::test form, or names), or
- a raw pytest stack trace/error output.

**Input:** $ARGUMENTS

## Workflow

### 1. Parse Failures

If input contains pytest output, extract:
- failing test node ids
- error types/messages
- file paths and line numbers
- assertion diffs and "E " lines
- traceback frames leading to the failure source

If input contains only test names:
- infer likely failure area by test naming and path conventions
- indicate missing info and what else would help

### 2. Identify Root Causes

Consider common pitfalls: mismatched API changes, fixtures not applied, timezone/locale, flakiness (timing, randomness), path issues, state leakage, dtype/float tolerances, dependency version changes.

Map each failure to a probable cause with evidence from the trace.

### 3. Propose Minimal, Targeted Code Changes

- Show unified diff patches with smallest surface area
- Keep public API stable unless tests explicitly require a change
- Preserve backward compatibility where possible
- For floating-point asserts, consider tolerances with `pytest.approx`
- For async, ensure proper event loop/await usage
- For IO/paths, use pathlib and temporary dirs/monkeypatch fixtures
- For time, use freezegun or timezone-aware datetimes

### 4. Improve Tests Only If Incorrect or Brittle

- If test assumptions are wrong, adjust tests minimally
- If flakiness is present, add deterministic seeds or waits properly (not arbitrary sleeps)

### 5. Verification Plan

- Exact pytest command(s) to re-run the failing scope first, then the full suite
- Mention any new dev/test dependencies added

### 6. Output Format

- **Summary**: one-liners for each failure with cause
- **Diffs**: one or more unified diffs with context
- **Commands**: shell commands to verify
- **Notes**: any risks or follow-ups

## Mocking Guidelines

- Prefer dependency inversion: pass collaborators into functions/classes so they can be replaced
- Mock behavior, not implementation details. Assert on inputs/outputs and visible effects
- Keep mocks local to tests using fixtures; avoid global patching
- Patch where the dependency is looked up, not where it's defined
- Use autospecced mocks: `unittest.mock.create_autospec` or `Mock(spec=Obj)`
- Set explicit `return_value`/`side_effect`. For exceptions, use `side_effect=SomeError()`
- For async functions, use `AsyncMock`; for context managers, implement `__enter__`/`__exit__`
- Time: `freezegun.freeze_time` or monkeypatch time functions
- Network: mock HTTP clients or use `responses`/`pytest-vcr`; never hit real endpoints in unit tests
- Filesystem: use `tmp_path` and monkeypatch to isolate CWD and env
- Avoid over-mocking: prefer real implementations for pure, fast, deterministic code
- Reset mocks between tests; use fixtures that yield and do cleanup

## Usage Examples

```bash
# By test name
/fix-pytest-failures tests/api/test_users.py::TestUsers::test_create_user

# By stack trace
/fix-pytest-failures "FAILURES... E AssertionError: ..."
```
