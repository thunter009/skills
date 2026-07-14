# Example Usage: add-pytest-coverage Skill

This document shows a complete example of using the `add-pytest-coverage` skill to improve test coverage.

## Scenario

You have a Python project with low test coverage and want to systematically improve it.

## Step 1: Generate Coverage Report

```bash
# Run tests with coverage
pytest --cov=src --cov-branch --cov-report=term-missing

# Output:
---------- coverage: platform darwin, python 3.11.9-final-0 ----------
Name                                    Stmts   Miss Branch BrPart  Cover   Missing
-------------------------------------------------------------------------------------
src/utils/parser.py                        50     50     12      0     0%   1-50
src/services/processor.py                  80     32     16      4    60%   15-20, 45->exit, 82-85, 100->105
src/services/validator.py                  40      8     10      2    80%   25-27, 40->42
src/api/routes.py                         120     60     24      6    50%   Multiple ranges
-------------------------------------------------------------------------------------
TOTAL                                     290    150     62     12    48%
```

## Step 2: Invoke the Skill

Paste this into Claude Code:

```text
I need to improve test coverage. Here's the current coverage report:

---------- coverage: platform darwin, python 3.11.9-final-0 ----------
Name                                    Stmts   Miss Branch BrPart  Cover   Missing
-------------------------------------------------------------------------------------
src/utils/parser.py                        50     50     12      0     0%   1-50
src/services/processor.py                  80     32     16      4    60%   15-20, 45->exit, 82-85, 100->105
src/services/validator.py                  40      8     10      2    80%   25-27, 40->42
src/api/routes.py                         120     60     24      6    50%   Multiple ranges
-------------------------------------------------------------------------------------
TOTAL                                     290    150     62     12    48%

Please focus on:
1. Getting parser.py to at least 80% coverage (it's at 0%)
2. Covering the missed branches in processor.py
3. Skip validator.py for now (already at 80%)

Constraints:
- Mock all network calls (we use httpx)
- Use tmp_path for filesystem operations
- Keep individual tests under 100ms
```

## Step 3: Expected Response - Test Plan

Claude will provide a prioritized test plan:

```markdown
## Coverage Analysis

**Current state:**
- src/utils/parser.py: 0% (0/50 lines, 0/12 branches)
- src/services/processor.py: 60% (48/80 lines, 12/16 branches)
- src/services/validator.py: 80% (32/40 lines, 8/10 branches) - SKIPPED per request
- src/api/routes.py: 50% (60/120 lines, 18/24 branches)

**Target:** Increase overall coverage from 48% → 70%+

## Prioritized Test Plan

### Priority 1: Zero Coverage - parser.py (0% → 80%+)

#### test_parser.py - New File

1. **test_parse_valid_json**
   - Covers: lines 10-15 (happy path)
   - Tests: Valid JSON input returns parsed dict

2. **test_parse_invalid_json**
   - Covers: lines 16-20 (error branch)
   - Tests: Invalid JSON raises ValueError

3. **test_parse_empty_input**
   - Covers: lines 21-25 (edge case)
   - Tests: Empty string returns empty dict

4. **test_parse_with_encoding**
   - Covers: lines 30-35, branch 30->32 vs 30->exit
   - Tests: UTF-8 vs ASCII encoding branches

5. **test_parse_file_not_found**
   - Covers: lines 40-45 (file I/O error)
   - Tests: FileNotFoundError handling

**Estimated coverage gain:** 0% → 85% (42/50 lines, 10/12 branches)

### Priority 2: Missed Branches - processor.py (60% → 85%+)

#### test_processor.py - Extend Existing

1. **test_process_with_retry_timeout**
   - Covers: line 45->exit (currently only 45->47 tested)
   - Tests: Timeout path in retry logic
   - Implementation: Mock httpx with side_effect=Timeout()

2. **test_process_validation_failure**
   - Covers: lines 15-20 (validation error path)
   - Tests: Invalid data triggers validation error

3. **test_process_error_callback**
   - Covers: lines 82-85 (error callback invocation)
   - Tests: Error callback receives correct error info

4. **test_process_cleanup_on_exception**
   - Covers: lines 100->105 (exception cleanup branch)
   - Tests: Resources cleaned up on exception

**Estimated coverage gain:** 60% → 90% (72/80 lines, 14/16 branches)

### Priority 3: API Routes - routes.py (50% → 75%+)

#### test_routes.py - Extend Existing

1. **test_health_endpoint**
   - Covers: Basic endpoint functionality
   - Tests: GET /health returns 200

2. **test_create_item_validation_errors**
   - Covers: Request validation branches
   - Tests: 422 on invalid request body

3. **test_get_item_not_found**
   - Covers: 404 error branch
   - Tests: GET /items/{id} returns 404 when not found

**Estimated coverage gain:** 50% → 75% (90/120 lines, 20/24 branches)

## Summary

- **Total new tests:** ~15 tests
- **Estimated time:** 2-3 hours
- **Coverage improvement:** 48% → 78% overall
- **Primary focus:** parser.py (0%→85%), processor.py (60%→90%)
```

## Step 4: Implementation Example

Claude will then provide test implementations:

### tests/utils/test_parser.py (New File)

```python
"""Tests for src/utils/parser.py - raising coverage from 0% to 85%+"""

import pytest
from pathlib import Path
from src.utils.parser import parse_json, parse_file, parse_with_encoding


class TestParseJson:
    """Test parse_json function - covers lines 10-25"""

    def test_parse_valid_json(self):
        """Happy path: valid JSON string → dict (lines 10-15)"""
        result = parse_json('{"key": "value"}')
        assert result == {"key": "value"}

    def test_parse_invalid_json(self):
        """Error branch: invalid JSON raises ValueError (lines 16-20)"""
        with pytest.raises(ValueError, match="Invalid JSON"):
            parse_json('{invalid json}')

    @pytest.mark.parametrize("input_str,expected", [
        ("", {}),
        ("{}", {}),
        ("[]", []),
    ])
    def test_parse_empty_inputs(self, input_str, expected):
        """Edge cases: empty inputs (lines 21-25)"""
        result = parse_json(input_str)
        assert result == expected


class TestParseWithEncoding:
    """Test encoding branches - covers lines 30-35, branch 30->32 vs 30->exit"""

    @pytest.mark.parametrize("encoding,content", [
        ("utf-8", '{"name": "José"}'),
        ("ascii", '{"name": "Jose"}'),
        ("latin-1", '{"name": "José"}'),
    ])
    def test_different_encodings(self, tmp_path, encoding, content):
        """Covers encoding branch points (line 30->32, 30->exit)"""
        file_path = tmp_path / f"test_{encoding}.json"
        file_path.write_text(content, encoding=encoding)

        result = parse_with_encoding(str(file_path), encoding=encoding)
        assert "name" in result


class TestParseFile:
    """Test file I/O error handling - covers lines 40-50"""

    def test_parse_file_not_found(self):
        """FileNotFoundError handling (lines 40-45)"""
        with pytest.raises(FileNotFoundError):
            parse_file("/nonexistent/path.json")

    def test_parse_file_permission_error(self, tmp_path, monkeypatch):
        """PermissionError handling (lines 46-50)"""
        file_path = tmp_path / "restricted.json"
        file_path.write_text('{"test": true}')

        # Simulate permission error
        def mock_open(*args, **kwargs):
            raise PermissionError("Access denied")

        monkeypatch.setattr("builtins.open", mock_open)

        with pytest.raises(PermissionError, match="Access denied"):
            parse_file(str(file_path))
```

### tests/services/test_processor.py (Extend Existing)

```python
"""Extend processor tests - raising coverage from 60% to 90%+"""

import pytest
from unittest.mock import Mock, patch, AsyncMock
import httpx
from src.services.processor import process_with_retry, process_with_validation


class TestProcessorRetryLogic:
    """Cover missed retry branches - line 45->exit"""

    @patch('httpx.AsyncClient.get')
    async def test_process_with_retry_timeout(self, mock_get):
        """
        Covers line 45->exit (timeout branch currently not covered)
        Tests that timeout exhausts retries and raises
        """
        # Simulate persistent timeout
        mock_get.side_effect = httpx.TimeoutException("Request timeout")

        with pytest.raises(httpx.TimeoutException):
            await process_with_retry("http://example.com", max_retries=3)

        # Verify retry attempts (1 initial + 3 retries)
        assert mock_get.call_count == 4

    @patch('httpx.AsyncClient.get')
    async def test_process_with_retry_eventual_success(self, mock_get):
        """
        Covers line 45->47 (success after retry)
        Complements existing test to ensure branch coverage
        """
        # Timeout twice, then succeed
        mock_get.side_effect = [
            httpx.TimeoutException("Timeout 1"),
            httpx.TimeoutException("Timeout 2"),
            AsyncMock(status_code=200, json=lambda: {"status": "ok"}),
        ]

        result = await process_with_retry("http://example.com", max_retries=3)

        assert result == {"status": "ok"}
        assert mock_get.call_count == 3


class TestProcessorValidation:
    """Cover validation error paths - lines 15-20"""

    def test_process_validation_failure(self):
        """
        Covers lines 15-20 (validation error path)
        Currently only happy path is tested
        """
        invalid_data = {"missing": "required_field"}

        with pytest.raises(ValueError, match="Validation failed"):
            process_with_validation(invalid_data)


class TestProcessorErrorCallback:
    """Cover error callback - lines 82-85"""

    def test_process_error_callback_invoked(self):
        """
        Covers lines 82-85 (error callback invocation)
        Tests that error callback receives correct error info
        """
        error_log = []

        def error_callback(error_info):
            error_log.append(error_info)

        with pytest.raises(ValueError):
            process_with_validation(
                {"bad": "data"},
                on_error=error_callback
            )

        assert len(error_log) == 1
        assert "Validation failed" in error_log[0]["message"]


class TestProcessorCleanup:
    """Cover exception cleanup - lines 100->105"""

    @patch('src.services.processor.cleanup_resources')
    def test_process_cleanup_on_exception(self, mock_cleanup):
        """
        Covers lines 100->105 (exception cleanup branch)
        Ensures resources cleaned up even on exception
        """
        def failing_process():
            raise RuntimeError("Processing failed")

        with pytest.raises(RuntimeError):
            try:
                failing_process()
            finally:
                cleanup_resources()  # This should always run

        mock_cleanup.assert_called_once()
```

## Step 5: Verification

Run tests and check coverage improvement:

```bash
# Run new tests
pytest tests/utils/test_parser.py -v

# Run extended processor tests
pytest tests/services/test_processor.py -v

# Check overall coverage
pytest --cov=src --cov-branch --cov-report=term-missing

# Expected output:
---------- coverage: platform darwin, python 3.11.9-final-0 ----------
Name                                    Stmts   Miss Branch BrPart  Cover   Missing
-------------------------------------------------------------------------------------
src/utils/parser.py                        50      7     12      2    85%   48-50, 35->exit
src/services/processor.py                  80      8     16      1    90%   110-112
src/services/validator.py                  40      8     10      2    80%   25-27, 40->42
src/api/routes.py                         120     30     24      4    75%   (various)
-------------------------------------------------------------------------------------
TOTAL                                     290     53     62      9    78%

# Coverage improved from 48% → 78% ✅
```

## Step 6: Iterate if Needed

If coverage goals aren't met, repeat with remaining gaps:

```bash
# Save updated coverage report
pytest --cov=src --cov-branch --cov-report=term-missing > coverage-round2.txt

# Provide to skill again with refined focus
```

## Tips for Best Results

1. **Be specific in notes**: Mention constraints, priorities, files to skip
2. **Include full coverage output**: Don't truncate the report
3. **Mention existing patterns**: "We use pytest fixtures from conftest.py"
4. **Set realistic targets**: 80-90% is excellent, 100% often impractical
5. **Iterate**: Do multiple rounds for large codebases

## Common Patterns the Skill Will Use

- **Parametrization** for branch coverage
- **Mocking** (httpx, requests, filesystem, time)
- **Fixtures** for reusable test setup
- **tmp_path** for filesystem isolation
- **pytest.raises** for error branches
- **caplog/capsys** for logging/output assertions
- **TestClient** for FastAPI routes
- **CliRunner** for Click commands

## Integration with Other Skills

- **fix-pytest**: If tests fail, use this skill to debug
- **refactor-tests**: After coverage is high, use this to improve test quality
- **CI integration**: Automate coverage checks in GitHub Actions
