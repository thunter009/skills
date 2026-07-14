# Coverage Report Template

Use this template when providing coverage reports to the `add-pytest-coverage` skill.

## Format 1: Direct Coverage Output (Recommended)

Simply paste the output from your pytest coverage command:

```bash
pytest --cov=src --cov-branch --cov-report=term-missing
```

**Example output:**

```text
---------- coverage: platform darwin, python 3.11.9-final-0 ----------
Name                                    Stmts   Miss Branch BrPart  Cover   Missing
-------------------------------------------------------------------------------------
src/utils/parser.py                        50     50     12      0     0%   1-50
src/services/processor.py                  50     20     10      5    60%   15-20, 45->exit, 82-85
src/services/validator.py                  30      5      8      2    85%   25-27, 40->42
-------------------------------------------------------------------------------------
TOTAL                                     130     75     30      7    42%
```

## Format 2: Delimited Format (Optional)

Use delimiters if you want to add specific notes or constraints:

```text
--- COVERAGE REPORT START ---
Name                                    Stmts   Miss Branch BrPart  Cover   Missing
-------------------------------------------------------------------------------------
src/utils/parser.py                        50     50     12      0     0%   1-50
src/services/processor.py                  50     20     10      5    60%   15-20, 45->exit, 82-85
src/services/validator.py                  30      5      8      2    85%   25-27, 40->42
-------------------------------------------------------------------------------------
TOTAL                                     130     75     30      7    42%
--- COVERAGE REPORT END ---

--- NOTES START ---
Priority:
1. Focus on src/utils/parser.py (0% coverage)
2. Cover missed branches in src/services/processor.py
3. Skip src/services/validator.py for now (already at 85%)

Constraints:
- Don't mock the database layer (use test DB)
- Keep tests under 5s total runtime
- Use fixtures from tests/conftest.py when possible
--- NOTES END ---
```

## Format 3: XML Snippet (Advanced)

If you have XML coverage output:

```xml
<coverage version="7.2.0">
  <packages>
    <package name="src.utils">
      <classes>
        <class name="parser.py" filename="src/utils/parser.py" line-rate="0.0" branch-rate="0.0">
          <lines>
            <line number="10" hits="0"/>
            <line number="11" hits="0" branch="true" missing-branches="exit"/>
          </lines>
        </class>
      </classes>
    </package>
  </packages>
</coverage>
```

## Common Coverage Commands

```bash
# Generate term-missing report (most useful)
pytest --cov=src --cov-branch --cov-report=term-missing

# Generate term-missing with explicit coverage config
pytest --cov=src --cov-branch --cov-report=term-missing --cov-config=.coveragerc

# Generate XML report (for CI/CD integration)
pytest --cov=src --cov-branch --cov-report=xml

# Generate HTML report (for detailed browsing)
pytest --cov=src --cov-branch --cov-report=html
# Then open htmlcov/index.html

# Save to file for skill input
pytest --cov=src --cov-branch --cov-report=term-missing > coverage.txt
```

## Understanding Coverage Output

### Columns Explained

- **Stmts**: Total executable statements in the file
- **Miss**: Statements not executed by tests
- **Branch**: Total conditional branches (if/else, try/except, etc.)
- **BrPart**: Partially covered branches (only one path taken)
- **Cover**: Coverage percentage (both lines and branches)
- **Missing**: Specific line numbers or branch paths not covered

### Branch Notation

- `45-50`: Lines 45 through 50 not executed
- `45->exit`: Branch from line 45 to exit not taken
- `45->47`: Branch from line 45 to line 47 not taken
- `45->52`: Branch from line 45 to line 52 not taken

### Priority Targets

1. **0% coverage files**: Completely untested
2. **Missed branches** (`->exit`, `->line`): Conditional paths
3. **Partially covered branches** (BrPart column): Test exists but missing edge cases
4. **Low coverage (<50%)**: Needs comprehensive testing

## Example Input to Skill

```text
Hi, I need to improve test coverage. Here's the current state:

---------- coverage: platform darwin, python 3.11.9-final-0 ----------
Name                                    Stmts   Miss Branch BrPart  Cover   Missing
-------------------------------------------------------------------------------------
src/utils/parser.py                        50     50     12      0     0%   1-50
src/services/processor.py                  50     20     10      5    60%   15-20, 45->exit, 82-85
-------------------------------------------------------------------------------------
TOTAL                                     100     70     22      5    30%

Please prioritize:
1. Get src/utils/parser.py to at least 80% coverage
2. Cover the retry logic in processor.py (line 45->exit is the timeout branch)
3. Keep tests fast - mock all network calls
```
