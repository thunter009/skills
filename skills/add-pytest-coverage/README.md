# add-pytest-coverage Skill

Systematically increase pytest test coverage by analyzing coverage reports and creating targeted tests without modifying production code.

## Quick Start

1. **Generate coverage report:**

   ```bash
   pytest --cov=src --cov-branch --cov-report=term-missing
   ```

2. **Invoke the skill** in Claude Code by pasting coverage output

3. **Review the test plan** before implementation

4. **Run verification** to confirm coverage improved

## What This Skill Does

- ✅ Analyzes coverage reports to identify gaps
- ✅ Creates prioritized test plans focusing on 0% files and missed branches
- ✅ Implements deterministic, fast, isolated tests
- ✅ Uses mocking and fixtures to avoid external dependencies
- ✅ Preserves all production code logic (tests only!)
- ✅ Provides verification commands to confirm improvements

## When to Use

Use this skill when you:

- Need to increase test coverage for a Python project
- Have a coverage report showing gaps
- Want systematic coverage improvement vs ad-hoc testing
- Need to meet coverage thresholds (e.g., 80% for CI/CD)

## Files in This Skill

```text
.claude/skills/add-pytest-coverage/
├── SKILL.md                          # Main skill definition with frontmatter
├── README.md                         # This file - overview and quick start
├── templates/
│   └── coverage-report-template.md  # Template for providing coverage data
└── examples/
    └── example-usage.md              # Complete end-to-end example
```

## Skill Structure

### SKILL.md

The main skill definition containing:

- **Frontmatter**: Metadata (name, description, permissions, when-to-use)
- **Instructions**: Comprehensive guide for the agent
- **Workflow**: Step-by-step process from analysis to verification
- **Patterns**: Code examples for common testing scenarios
- **Constraints**: Rules for maintaining code quality

### Templates

- **coverage-report-template.md**: Shows how to format coverage input
  - Direct output format (recommended)
  - Delimited format with notes
  - XML snippet format
  - Common pytest-cov commands

### Examples

- **example-usage.md**: Complete walkthrough showing:
  - Real coverage report
  - Skill invocation
  - Test plan generation
  - Test implementation
  - Verification steps
  - Iterative improvement

## Key Features

### Prioritization

1. **0% coverage files** (untested modules)
2. **Missed branches** (conditional paths not taken)
3. **Partially covered branches** (one path tested, others missed)

### Testing Techniques

- **Parametrization**: `@pytest.mark.parametrize` for branch coverage
- **Mocking**: Mock network, filesystem, time for determinism
- **Fixtures**: Reusable test setup in `conftest.py`
- **Isolation**: `tmp_path` for filesystem, `monkeypatch` for env vars
- **Error testing**: `pytest.raises` for exception paths
- **Assertions**: `caplog` for logs, `capsys` for output

### Quality Guarantees

Tests are always:

- ⚡ **Fast**: Mock slow operations (network, disk, time)
- 🎯 **Deterministic**: Same input = same output
- 🔒 **Isolated**: No shared state or external dependencies
- 🛡️ **Safe**: No production code changes

## Usage Example

```text
I need to improve coverage. Current state:

---------- coverage: platform darwin, python 3.11.9-final-0 ----------
Name                        Stmts   Miss Branch BrPart  Cover   Missing
------------------------------------------------------------------------
src/utils/parser.py            50     50     12      0     0%   1-50
src/services/processor.py      80     32     16      4    60%   15-20, 45->exit
------------------------------------------------------------------------
TOTAL                         130     82     28      4    37%

Please focus on parser.py first, then processor.py missed branches.
Keep tests fast (mock all I/O).
```

The skill will respond with:

1. **Test Plan**: Prioritized list of tests with line coverage targets
2. **Implementation**: Complete test code with fixtures and mocks
3. **Verification**: Commands to run tests and check coverage
4. **Notes**: Assumptions, risks, hard-to-reach branches

## Integration

### With fix-pytest Skill

If tests fail during implementation:

1. Copy pytest failure output
2. Use `fix-pytest` skill to diagnose and fix
3. Re-run coverage verification

### With CI/CD

The skill produces tests suitable for CI pipelines:

- Fast execution (<2min typical)
- No external dependencies
- Deterministic results
- Coverage tracking integrated

### With Coverage Tools

Compatible with:

- **pytest-cov**: Primary coverage tool
- **coverage.py**: Underlying coverage measurement
- **codecov/coveralls**: CI coverage reporting

## Best Practices

### Before Using Skill

1. Run existing tests to ensure they pass
2. Generate fresh coverage report
3. Identify priority files/branches
4. Note any constraints (mocking patterns, fixtures)

### During Implementation

1. Review test plan before writing code
2. Implement tests incrementally (verify after each batch)
3. Keep tests focused and well-documented
4. Reference coverage line numbers in test docstrings

### After Implementation

1. Run full test suite to ensure no breakage
2. Verify coverage improved materially
3. Check tests are fast (<100ms per test ideal)
4. Update CI/CD thresholds if needed

## Common Scenarios

### Scenario 1: Untested Module

**Input:** File at 0% coverage

**Output:** Complete test suite covering:

- Happy paths
- Error handling
- Edge cases
- All branches

### Scenario 2: Missed Branches

**Input:** File at 60% with missed conditional branches

**Output:** Parametrized tests targeting:

- Uncovered if/else paths
- Exception handling branches
- Early returns/exits
- Retry/timeout logic

### Scenario 3: Integration Tests

**Input:** API routes or CLI commands needing coverage

**Output:** Integration tests using:

- FastAPI TestClient
- Click CliRunner
- Mocked databases/services
- Request/response validation

## Constraints and Limits

### What the Skill Will Do

✅ Create new tests in `tests/`
✅ Add fixtures to `conftest.py`
✅ Mock external dependencies
✅ Document hard-to-reach branches
✅ Provide verification commands

### What the Skill Won't Do

❌ Modify production code in `src/`
❌ Create untestable refactoring seams
❌ Add backwards compatibility hacks
❌ Make tests dependent on test execution order
❌ Use real network/filesystem/databases

## Verification Commands

After skill completes, run:

```bash
# Quick test run
pytest -q

# Full coverage report
pytest --cov=src --cov-branch --cov-report=term-missing

# HTML report for detailed browsing
pytest --cov=src --cov-branch --cov-report=html
open htmlcov/index.html

# Targeted test run
pytest tests/path/to/new_test.py -v

# Check specific module
pytest --cov=src/utils/parser --cov-branch --cov-report=term-missing
```

## Troubleshooting

### Tests are slow (>5s total)

- Ensure all network calls are mocked
- Use `tmp_path` instead of real filesystem
- Mock time-dependent operations
- Check for accidental database connections

### Coverage didn't improve

- Verify tests are actually running (pytest -v)
- Check test discovery (tests in proper location)
- Ensure no test skips or xfails
- Review parametrization coverage

### Tests are flaky

- Check for time dependencies (freeze time)
- Ensure proper isolation (no shared fixtures)
- Seed randomness if tests use random data
- Verify cleanup in teardown/fixtures

## Resources

- **SKILL.md**: Full skill specification
- **templates/coverage-report-template.md**: Input format guide
- **examples/example-usage.md**: Complete walkthrough
- [pytest documentation](https://docs.pytest.org/)
- [pytest-cov documentation](https://pytest-cov.readthedocs.io/)
- [coverage.py documentation](https://coverage.readthedocs.io/)

## License

This skill is part of the notice-wise-backend project. See project LICENSE for details.

## Contributing

To improve this skill:

1. Test it on your codebase
2. Note any gaps or unclear instructions
3. Submit feedback via project issues
4. Propose enhancements to SKILL.md

---

**Ready to improve your test coverage?** Generate a coverage report and invoke this skill!
