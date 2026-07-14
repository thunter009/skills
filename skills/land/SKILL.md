---
name: land
description: Pre-landing closeout — review, ubs scan, fix findings, then ship.
when-to-use:
- land this, ready to ship, pre-PR closeout
- After non-trivial work on a branch before opening a PR
permissions:
- read
- write
- bash
category: release
---

# /land — full pre-landing closeout

A four-phase wrapper that gates code quality before handing off to the ship workflow.
Heavy lifting is delegated to focused skills. Each phase checkpoints before proceeding.

**When NOT to use:** trivial single-file edits — just commit directly.

## Phase 1 — Structured code review

Run a structured code review of the local branch following the **autoreview** skill:

- In this repo: `skills/autoreview/SKILL.md`
- Outside this repo: `~/.claude/skills/autoreview/SKILL.md`

Scope the review to changed files only (`git diff --name-only main...HEAD` or the
relevant base branch). Report findings before proceeding — do not silently swallow them.

## Phase 2 — Static analysis with ubs

Run `ubs` on all files changed relative to the base branch:

```bash
ubs $(git diff --name-only main...HEAD)
```

Adapt `main` to the repo's integration branch (`dev`, `master`, etc.). If the diff is
empty (no changed files), skip this phase and note it.

Exit 0 → clean, move on. Exit >0 → treat every finding as a Phase 3 item.

## Phase 3 — Fix findings

Consolidate findings from Phases 1 and 2. For each:

1. Judge severity: HIGH/MEDIUM/LOW (bugs and security → HIGH; style → LOW).
2. Fix all HIGH and MEDIUM findings now. LOW findings: fix if trivial, else note as
   follow-ups.
3. After fixes, re-run `ubs` on the edited files to confirm clean.
4. If Phase 1 surfaced design-level concerns (not just code issues), pause and surface
   them to the user before proceeding — do not silently resolve architectural questions.

If there are no findings, report "clean" and move on.

## Phase 4 — Ship

Follow the **ship** skill for the full landing workflow (sync, test, split commits, PR):

- In this repo: `skills/ship/SKILL.md`
- Outside this repo: `~/.claude/skills/ship/SKILL.md`

Do not skip ship's confirmation gates. The code-review + ubs passes above are additive,
not a substitute for ship's test/lint/typecheck pipeline.

## Output

Close with a summary table:

| Phase | Result |
|---|---|
| 1 Review | N findings (H/M/L breakdown) / clean |
| 2 ubs | N findings fixed / clean |
| 3 Fixes | fixed N, deferred N as follow-ups |
| 4 Ship | PR #N opened / link |
