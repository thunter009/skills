---
name: pr-review
description: Review a pull request with structured findings and merge-risk checks.
when-to-use:
- review PR, pull request feedback, PR audit
- Before merging
permissions:
- read
- bash
category: release
---

# Pull Request Review

Thorough, structured review of a pull request.

**PR to review:** $ARGUMENTS

## Step 1: Read the checklist

Read `references/checklist.md` relative to this skill's directory. This file defines review categories, critical vs informational classification, output format, and suppressions.

**If the checklist cannot be read, STOP and report the error.** Do not proceed without it.

## Step 2: Fetch PR details

1. If no PR number/URL provided: find the PR for the current branch. If on main branch, list open PRs and ask which one to review.
2. Fetch PR details using GitHub CLI
3. Check existing review comments and status checks
4. If checks are failing, examine failure details

```bash
gh pr view          # PR details, reviews, status checks
gh pr diff          # Code changes
gh pr checks        # Detailed check status and failure logs
gh run view         # Workflow run details if checks are failing
```

Check `.github/workflows/` to understand what CI/CD checks are configured.

## Step 3: Read project conventions

Before reviewing, check for AGENTS.md or CLAUDE.md in the repo root. These define project conventions, preferred patterns, and known intentional deviations. A finding that contradicts a documented convention is a false positive — discard it.

## Step 4: Two-pass review

Apply the checklist against the diff in two passes:

1. **Pass 1 (CRITICAL — blocking):** SQL & Data Safety, Race Conditions & Concurrency, LLM Output Trust Boundary. These can block merge.
2. **Pass 2 (INFORMATIONAL — non-blocking):** All remaining categories. Included in output but do not block.

Also check for:
- **Missing Logic**: Related code that should be updated but wasn't
- **Missing Tests**: Test cases that should exist for the new functionality

Follow the output format specified in the checklist. Respect the suppressions — do NOT flag items listed in the "DO NOT flag" section.

### Verify before flagging

**For each potential finding, read the relevant source file and verify the issue exists in the current code.** Do not flag issues based on the diff alone — context outside the diff often resolves apparent problems. ~25-30% of automated review findings are false positives (from session evidence). Discard false positives silently.

### Optional: local verification for critical findings

For critical findings involving runtime behavior (crashes, data corruption, race conditions), consider running a targeted test or reproducing locally if the project has a dev environment. This catches real bugs that code-reading alone can miss.

## Step 5: Output findings

Use the terse output format from the checklist: one line problem, one line fix, `file:line` references. No preamble.

- **If critical issues found:** Output all findings, then for each critical issue use AskUserQuestion with the problem, recommended fix, and options (A: Fix it now, B: Acknowledge, C: False positive). Apply fixes for any A choices.
- **If only informational issues found:** Output findings. No further action needed.
- **If no issues found:** Output `Review: No issues found.`

**End with an overall recommendation:** APPROVE, REQUEST CHANGES, or COMMENT.
- REQUEST CHANGES if any critical/blocking issues remain unresolved
- APPROVE if no critical issues (informational findings are acceptable)
- COMMENT if unsure or need more context

## Important Rules

- **Read the FULL diff before commenting.** Do not flag issues already addressed in the diff.
- **Read-only by default.** Only modify files if the user explicitly chooses "Fix it now" on a critical issue.
- **Be terse.** One line problem, one line fix. No preamble, no "looks good overall."
- **Only flag real problems.** Skip anything that's fine.
- **Respect suppressions.** The checklist's suppressions section exists to reduce false positives.
