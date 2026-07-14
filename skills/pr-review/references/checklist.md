# Review Checklist

## Instructions

Review the diff for the issues listed below. Be specific — cite `file:line` and suggest fixes. Skip anything that's fine. Only flag real problems.

**Two-pass review:**
- **Pass 1 (CRITICAL):** These block merge. Run first.
- **Pass 2 (INFORMATIONAL):** Included in review output but do not block.

**Output format:**

```
Review: N issues (X critical, Y informational)

**CRITICAL** (blocking):
- [file:line] Problem description
  Fix: suggested fix

**INFORMATIONAL** (non-blocking):
- [file:line] Problem description
  Fix: suggested fix
```

If no issues found: `Review: No issues found.`

Be terse. For each issue: one line describing the problem, one line with the fix. No preamble, no summaries, no "looks good overall."

---

## Review Categories

### Pass 1 — CRITICAL

### SQL & Data Safety
- String interpolation/concatenation in SQL queries — use parameterized queries or the ORM's query builder
- TOCTOU races: check-then-set patterns that should be atomic (use `WHERE` conditions on updates, `INSERT ... ON CONFLICT`, or transactions with appropriate isolation)
- Bypassing ORM validations on fields that have or should have constraints (e.g., raw column updates, `force_update`, `save(validate: false)`)
- N+1 queries: eager loading missing for associations accessed in loops or templates

### Race Conditions & Concurrency
- Read-check-write without uniqueness constraint or conflict handling — concurrent calls can create duplicates
- Upsert/find-or-create on columns without unique DB index
- Status transitions that don't use atomic conditional updates — concurrent updates can skip or double-apply transitions
- Rendering user-controlled data as raw HTML without sanitization (XSS)

### LLM Output Trust Boundary
- LLM-generated values (emails, URLs, names) written to DB or passed to external services without format validation — add lightweight guards (regex, URL parse, strip) before persisting
- Structured LLM output (arrays, objects) accepted without type/shape checks before database writes or downstream processing
- LLM output used to construct queries, commands, or file paths without sanitization (injection risk)

### Pass 2 — INFORMATIONAL

### Conditional Side Effects
- Code paths that branch on a condition but forget to apply a side effect on one branch, creating inconsistent state
- Log messages that claim an action happened but the action was conditionally skipped

### Magic Numbers & String Coupling
- Bare numeric literals used in multiple files — should be named constants
- Error message strings used as query filters or match targets elsewhere (grep for the string — is anything matching on it?)

### Dead Code & Consistency
- Variables assigned but never read
- Version mismatch between PR title and version/changelog files
- Changelog entries that describe changes inaccurately
- Comments/docstrings that describe old behavior after the code changed

### LLM Prompt Issues
- 0-indexed lists in prompts (LLMs reliably return 1-indexed)
- Prompt text listing tools/capabilities that don't match what's actually wired up
- Word/token limits stated in multiple places that could drift

### Test Gaps
- Negative-path tests that assert type/status but not side effects (field populated? callback fired? external service called?)
- Assertions on string content without checking format
- Missing assertions that a code path should explicitly NOT call an external service
- Security enforcement features (auth, rate limiting, blocking) without integration tests verifying the enforcement path

### Crypto & Entropy
- Truncation instead of hashing — less entropy, easier collisions
- Non-cryptographic random (`Math.random`, `random.random`, `rand()`) for security-sensitive values — use cryptographic alternatives (`crypto.randomBytes`, `secrets`, `SecureRandom`)
- Non-constant-time comparisons (`==`) on secrets or tokens — vulnerable to timing attacks

### Type Coercion at Boundaries
- Values crossing language/serialization boundaries where type could change (numeric vs string) — normalize before hashing or comparison
- Hash/digest inputs that don't normalize types before serialization

### Time & Date Safety
- Date-key lookups that assume "today" covers a full 24h window
- Mismatched time windows between related features
- Timezone-naive datetime comparisons across different timezone contexts

---

## Gate Classification

```
CRITICAL (blocks merge):              INFORMATIONAL (in review output):
├─ SQL & Data Safety                  ├─ Conditional Side Effects
├─ Race Conditions & Concurrency      ├─ Magic Numbers & String Coupling
└─ LLM Output Trust Boundary          ├─ Dead Code & Consistency
                                       ├─ LLM Prompt Issues
                                       ├─ Test Gaps
                                       ├─ Crypto & Entropy
                                       ├─ Type Coercion at Boundaries
                                       └─ Time & Date Safety
```

---

## Suppressions — DO NOT flag these

- "X is redundant with Y" when the redundancy is harmless and aids readability
- "Add a comment explaining why this threshold/constant was chosen" — thresholds change during tuning, comments rot
- "This assertion could be tighter" when the assertion already covers the behavior
- Consistency-only changes (reformatting code to match a neighbor's style when both are correct)
- "Regex doesn't handle edge case X" when the input is constrained and X never occurs in practice
- "Test exercises multiple guards simultaneously" — tests don't need to isolate every guard
- Eval threshold changes that are tuned empirically
- Harmless no-ops (e.g., filtering an element that's never in the collection)
- ANYTHING already addressed in the diff you're reviewing — read the FULL diff before commenting
