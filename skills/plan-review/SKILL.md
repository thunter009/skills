---
name: plan-review
description: Audit an implementation plan before coding begins.
when-to-use:
- review plan, audit plan, check implementation plan
- Before starting complex work
permissions:
- read
- bash
category: pm
---

# Plan Review

Audit **$ARGUMENTS** before coding begins.

Do NOT make code changes. Do NOT start implementation. Review only.

## Step 1: Gather Context

```bash
git log --oneline -20
git diff main --stat 2>/dev/null
```

Read CLAUDE.md/AGENTS.md for project conventions. Scan issue tracker (beads, Linear) for items this plan touches.

## Step 2: Scope Challenge

### Premise check
1. Is this the right problem? Could a different framing yield a simpler solution?
2. What would happen if we did nothing? Real pain or hypothetical?
3. What existing code already covers part of this? Does the plan rebuild something that could be reused?

### Mode selection

Infer from context (user can override):

| Signal | Default mode |
|--------|-------------|
| Greenfield feature | **EXPAND** — push scope up, dream big |
| Bug fix / hotfix | **HOLD** — maximum rigor within scope |
| >15 files touched | **REDUCE** — strip to essentials |
| Refactor | **HOLD** |

State the mode and rationale. Ask only if ambiguous.

### Mode-specific analysis

**EXPAND:** What's the 10x version for 2x effort? What adjacent improvements would delight users? What makes this a platform, not just a feature?

**HOLD:** Complexity check — >8 files or >2 new modules = smell. Minimum change set — flag anything deferrable.

**REDUCE:** Ruthless cut — absolute minimum that ships value. What can be a follow-up vs must ship together?

## Step 3: Critical Checks

Run through these. Flag issues, don't stop for clean passes:

### Architecture
- Dependency graph: what's now coupled that wasn't before?
- Data flow: happy path, nil/empty, error path for each new integration point
- Rollback posture: if this breaks, how do you undo it?

### Error map
For each new function/service that can fail:

| Codepath | What can go wrong | Rescued? | User sees |
|----------|-------------------|----------|-----------|
| ... | ... | ... | ... |

Flag any row where **Rescued=N AND User sees=Silent** as a CRITICAL GAP.

### Verification
- For each planned deliverable: what is the *specific verification step* that confirms it works? (not "run tests" — which test, what assertion)
- Premature closure check: past sessions show beads/plans marked done when the code doesn't actually work. Flag any deliverable without a concrete verification command.

### Blast radius
- Does any task touch >N existing files? (>15 = suggest splitting)
- Are there cross-bead contradictions? (different assumptions about APIs, schemas, config)
- Does the plan account for existing users / data migration?

## Step 4: Verdict

One of:
- **GO** — plan is sound, proceed to implementation
- **GO WITH CHANGES** — list specific changes needed, then proceed
- **RETHINK** — fundamental issues, needs reshaping before implementation

For each issue found, state: problem, recommendation, severity (blocking / non-blocking).

Keep the output terse. No ASCII diagrams, no failure mode registries, no completion summary tables. Just: what's wrong, how to fix it, go or no-go.

## Step 5 (optional): Grill Mode

If the user asks to be grilled (or the verdict is RETHINK and they want to work through it), switch from report mode to interview mode:

- Ask **one question at a time**, walking down each branch of the design tree, resolving dependencies between decisions one-by-one. Provide your recommended answer with each question (AskUserQuestion fits this).
- If a question can be answered by exploring the codebase, explore instead of asking.
- Stress-test domain relationships with concrete scenarios that probe edge cases. When the user states how something works, check whether the code agrees — surface contradictions.

**Update docs inline as decisions crystallise — don't batch:**

- If the repo keeps a domain glossary (`CONTEXT.md`): when a fuzzy or conflicting term gets resolved, update it right there. Glossary only — no implementation details.
- Offer an ADR (`docs/adr/NNNN-slug.md`, 1-3 sentences is enough) only when all three hold: **hard to reverse**, **surprising without context**, **the result of a real trade-off**. If any is missing, skip it.
- Create these files lazily — only when there's something to write.
