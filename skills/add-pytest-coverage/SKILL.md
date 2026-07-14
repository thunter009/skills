---
name: add-pytest-coverage
description: Add or expand pytest coverage without changing production logic.
when-to-use:
- add coverage, expand pytest coverage, cover this module
- When Python code needs tests for uncovered paths
permissions:
- read
- write
- bash
category: testing
---

# Add Pytest Coverage Skill

This skill helps you systematically increase pytest test coverage by analyzing coverage reports and creating targeted tests for uncovered code paths.

## Non-Negotiable Checklist

Before marking complete, verify ALL of these:

1. **Every `raise`/`except`/guard clause** has a test using `pytest.raises`
2. **Use `@pytest.mark.parametrize`** or produce >= 2x the number of functions under test
3. **All public functions** have at least one test
4. **All tests pass**: `pytest -q` exits 0
5. **No production code changed** — only `tests/` modified

## Overview

You are an expert Python developer and test engineer. You will receive a coverage report and optional notes. Your task is to create and/or update tests to increase coverage while preserving existing production logic.

## Input Format

The user will provide coverage report data, typically in one of these formats:

1. **Plain text coverage report** from `pytest --cov=src --cov-branch --cov-report=term-missing`
2. **XML coverage snippet** from `pytest --cov=src --cov-branch --cov-report=xml`
3. **Delimited format** (optional):

```text
--- COVERAGE REPORT START ---
... your coverage output ...
--- COVERAGE REPORT END ---
--- NOTES START ---
... any constraints or priorities ...
--- NOTES END ---
```

## Goals

1. **Increase coverage**: Focus on both line and branch coverage
   - Priority 1: 0% or very low-coverage modules
   - Priority 2: Missed branches in medium-coverage files
   - Priority 3: Edge cases and error handling paths

2. **Exercise real code paths**: Cover exact lines/branches marked as "Missing" in reports

3. **Preserve production logic**: No changes to `src/` code logic

## Rules and Constraints

### Production Code (src/)

- **MUST remain unchanged** in logic
- If testability seams are absolutely necessary, use:
  - pytest fixtures
  - monkeypatching (env, I/O, time, network)
  - local test doubles in `tests/` (stubs/fakes)

### Test Quality Requirements

Tests must be:

- **Deterministic**: Same input = same output, every time
- **Fast**: Mock network, filesystem, time-dependent operations
- **Isolated**: No shared state between tests

### Testing Techniques

#### Mocking External Dependencies

```python
# No real network calls
@patch('requests.get')
def test_api_call(mock_get):
    mock_get.return_value.json.return_value = {"status": "ok"}
    # test code

# Filesystem isolation
def test_file_operations(tmp_path):
    test_file = tmp_path / "test.txt"
    # test code

# Time control
@freeze_time("2025-01-15 12:00:00")
def test_time_dependent():
    # test code
```

#### Web/CLI Testing

```python
# FastAPI
from fastapi.testclient import TestClient
client = TestClient(app)

# Click CLI
from click.testing import CliRunner
runner = CliRunner()
result = runner.invoke(cli_command, ['--arg', 'value'])
```

#### Branch Coverage

```python
# Use parametrization
@pytest.mark.parametrize("input,expected", [
    (0, "zero"),
    (1, "one"),
    (-1, "negative"),
])
def test_branches(input, expected):
    assert classify(input) == expected

# Error branches
with pytest.raises(ValueError, match="invalid"):
    function_that_raises()
```

## Workflow

### 1. Parse Coverage Report

Extract from the coverage section:

- Files at 0% or very low coverage
- Files with many missed branches
- Exact line ranges (e.g., `72-81`)
- Branch arrows (e.g., `72->81` vs `72->exit`)

### 2. Create Test Plan

Produce a prioritized plan mapping:

- Each file or range → specific test cases
- Rationale for each test (which branch/line it covers)
- Dependencies needed (fixtures, mocks)

**Coverage-driven approach:** For each uncovered line range in the report, read the source to identify the branch condition guarding those lines, then write a test that forces execution through that branch. Every exception handler (`except`, `raise`, guard clause) needs its own test case using `pytest.raises`.

**Minimum test count heuristic:** Aim for at least 2x the number of functions under test. A module with 5 functions should produce at least 10 test functions (happy path + at least one edge case per function). Use `@pytest.mark.parametrize` to cover multiple input variants efficiently.

**Example Plan Format:**

```markdown
## Test Plan

### Priority 1: Zero Coverage Files

1. **src/utils/parser.py (0% coverage)**
   - Test `parse_input()` happy path → covers lines 10-15
   - Test `parse_input()` with invalid data → covers lines 16-20, error branch
   - Test `parse_input()` with empty input → covers lines 21-23

### Priority 2: Missed Branches

2. **src/services/processor.py (60% coverage, 15 missed branches)**
   - Test retry logic timeout path → covers lines 45->exit (currently 45->47 only)
   - Test error callback invocation → covers lines 82-85
```

### 3. Implement Tests Incrementally

Write tests in small, focused commits:

```bash
# Start with 0% files
# Then cover missed branches in medium coverage modules
```

### 4. Verify Changes

Run tests and coverage:

```bash
# Quick test run
pytest -q

# Full coverage report
pytest --cov=src --cov-branch --cov-report=term-missing

# Targeted test run
pytest -q tests/path/test_file.py::TestClass::test_case
```

### 5. Integration with fix-pytest

If tests fail during this process:

1. Capture the pytest failure output
2. Use the `fix-pytest` skill/command with the failing output
3. Apply minimal fixes consistent with coverage goals
4. Re-run tests

## Testing Patterns

### Parametrization for Branch Coverage

```python
@pytest.mark.parametrize("env_var,expected_format", [
    ("JSON", "json"),
    ("PLAIN", "plain"),
    (None, "plain"),  # default branch
])
def test_logging_format(monkeypatch, env_var, expected_format):
    if env_var:
        monkeypatch.setenv("LOG_FORMAT", env_var)
    assert get_log_format() == expected_format
```

### Error Handling

```python
def test_network_timeout_retry(monkeypatch):
    """Covers utils/network.py:180-181 retry logic"""
    mock_request = Mock(side_effect=[Timeout(), {"status": "ok"}])
    monkeypatch.setattr("requests.get", mock_request)

    result = fetch_with_retry("http://example.com")
    assert result == {"status": "ok"}
    assert mock_request.call_count == 2
```

### CLI Testing

```python
def test_cli_help_flag():
    """Covers cli/main.py:45->exit (help branch)"""
    runner = CliRunner()
    result = runner.invoke(main, ['--help'])
    assert result.exit_code == 0
    assert "Usage:" in result.output

def test_cli_missing_required_arg():
    """Covers cli/main.py:50->exit (error branch)"""
    runner = CliRunner()
    result = runner.invoke(main, [])
    assert result.exit_code != 0
    assert "required" in result.output.lower()
```

### Logging Assertions

```python
def test_error_logging(caplog):
    """Covers services/processor.py:120-122 error logging"""
    with caplog.at_level(logging.ERROR):
        process_invalid_data({"bad": "data"})

    assert "Invalid data format" in caplog.text
    assert caplog.records[0].levelname == "ERROR"
```

### Filesystem Isolation

```python
def test_config_file_loading(tmp_path):
    """Covers utils/config.py:35-40 file loading"""
    config_file = tmp_path / "config.yaml"
    config_file.write_text("key: value\n")

    result = load_config(str(config_file))
    assert result["key"] == "value"
```

### Mocking Best Practices

```python
from unittest.mock import create_autospec, AsyncMock

def test_external_api_call():
    """Use create_autospec for type-safe mocks"""
    mock_client = create_autospec(APIClient)
    mock_client.fetch.return_value = {"data": "test"}

    result = process_api_data(mock_client)
    assert result["data"] == "test"

async def test_async_operation():
    """Use AsyncMock for async functions"""
    mock_fetch = AsyncMock(return_value={"status": "ok"})

    result = await async_handler(mock_fetch)
    assert result["status"] == "ok"
```

## Deliverables

Your output should include:

### 1. Test Plan (Markdown)

```markdown
## Coverage Analysis

**Current state:**
- src/utils/parser.py: 0% (0/50 lines)
- src/services/processor.py: 60% (30/50 lines, 15 missed branches)

## Prioritized Test Plan

### Priority 1: Zero Coverage
1. src/utils/parser.py
   - test_parse_valid_input() → lines 10-15
   - test_parse_invalid_input() → lines 16-20, error branch
   ...

### Priority 2: Missed Branches
1. src/services/processor.py
   - test_retry_timeout() → lines 45->exit
   ...
```

### 2. Test Implementation (Code)

- New test files under `tests/` mirroring `src/` structure
- Shared fixtures in `tests/conftest.py`
- Helper fakes/mocks in `tests/utils/` when useful
- Minimal changes to `pytest.ini` or `pyproject.toml` (only if required)

### 3. Verification Commands

```bash
# Run new tests
pytest -q tests/path/to/new_test.py

# Check coverage improvement
pytest --cov=src --cov-branch --cov-report=term-missing

# Run specific test scope
pytest -q -k "keyword and module"
```

### 4. Notes

Document:

- Any risks or assumptions
- Hard-to-reach branches and how they were handled
- Test-only seams introduced (fixtures, mocks)
- Non-obvious setups (with comments referencing coverage lines)

## Example Micro-Tests

These are acceptable lightweight tests for coverage:

```python
# Environment variable branch
@pytest.mark.parametrize("log_format", ["JSON", "PLAIN"])
def test_logging_format_branch(monkeypatch, log_format):
    """Covers utils/logging.py:25-28 format branches"""
    monkeypatch.setenv("LOG_FORMAT", log_format)
    # test implementation

# Network timeout/retry
def test_network_retry_on_timeout(monkeypatch):
    """Covers utils/network.py:80-85 retry logic"""
    mock = Mock(side_effect=[Timeout(), {"ok": True}])
    monkeypatch.setattr("requests.get", mock)
    # test implementation

# CLI help/exit branch
def test_cli_help_exits_zero():
    """Covers cli/main.py:45->exit (--help branch)"""
    runner = CliRunner()
    result = runner.invoke(main, ['--help'])
    assert result.exit_code == 0
```

## Common Fixtures

Add shared fixtures to `tests/conftest.py`:

```python
import pytest
from pathlib import Path

@pytest.fixture
def sample_data_dir(tmp_path):
    """Isolated directory for test data"""
    data_dir = tmp_path / "data"
    data_dir.mkdir()
    return data_dir

@pytest.fixture
def mock_env_vars(monkeypatch):
    """Clean environment for tests"""
    monkeypatch.delenv("API_KEY", raising=False)
    monkeypatch.delenv("DEBUG", raising=False)
    return monkeypatch

@pytest.fixture
def freeze_time_2025():
    """Fixed time for deterministic tests"""
    with freeze_time("2025-01-15 12:00:00"):
        yield
```

## Reminder: Constraints

- **Keep changes strictly to `tests/`** unless configuration for discovery is required
- **No production logic changes** in `src/`
- **Document non-obvious setups** with comments referencing coverage lines
- **Run `pytest --cov` after each test addition** to verify coverage increase
- **Ensure all tests pass** before completing the task

## Verification

Before marking complete:

```bash
# All tests must pass
pytest -q

# Coverage should materially increase
pytest --cov=src --cov-branch --cov-report=term-missing

# Optional: Check specific modules
pytest --cov=src/utils --cov-branch --cov-report=term-missing
```

## Integration Points

- **fix-pytest skill**: Use if tests fail during implementation
- **Coverage tools**: Works with pytest-cov, coverage.py
- **CI/CD**: Tests should be fast enough for CI (<2min total)

---

## Usage Instructions

1. **Gather coverage report**:

   ```bash
   pytest --cov=src --cov-branch --cov-report=term-missing > coverage.txt
   ```

2. **Invoke skill** with coverage report and optional notes

3. **Review test plan** before implementation

4. **Implement tests incrementally**, verifying coverage after each batch

5. **Run final verification** to ensure all tests pass and coverage improved
