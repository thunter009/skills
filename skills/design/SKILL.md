---
name: design
description: Take a feature idea from fuzzy to build-ready — grill, prototype, then plan.
when-to-use:
- design this feature, help me think through X, turn this idea into tickets
- Before starting work on anything with unclear scope or state model
permissions:
- read
- write
- bash
category: code
---

# /design — idea to build-ready plan

Three phases that progressively de-risk a feature before a line of production code is
written. Wrapper delegates to focused skills; each phase gates the next.

**When NOT to use:** small well-understood changes — just write the code.

## Phase 1 — Grill the plan

Run Step 5 (grill mode) from the **plan-review** skill:

- In this repo: `skills/plan-review/SKILL.md`
- Outside this repo: `~/.claude/skills/plan-review/SKILL.md`

Key constraints for this phase:

- Ask **one question at a time**. Never fire a numbered list of questions.
- Explore the codebase to answer questions yourself before asking the user — only escalate
  genuine ambiguities that require product judgment.
- As decisions crystallise, write them inline: update `CONTEXT.md`, ADRs, or a
  `DESIGN.md` scratchpad so the plan stays in the repo, not just in the conversation.
- Continue until the plan can answer: *what changes, why, how it fits the existing
  architecture, and what "done" looks like*.

Exit criterion: no HIGH-severity open questions remain (security, data model, public API
shape, or irreversible architectural choices). LOW questions are acceptable; note them.

## Phase 2 — Prototype (conditional)

If one or more **load-bearing uncertainties** remain after Phase 1 — state model
ambiguity, novel UI interaction, performance unknown — build a throwaway prototype to
answer the question before committing to a design.

Follow the **prototype** skill:

- In this repo: `skills/prototype/SKILL.md`
- Outside this repo: `~/.claude/skills/prototype/SKILL.md`

The prototype is disposable. Capture only the answer it produced (e.g. "state machine
with 4 states is sufficient; event sourcing not needed") in the design doc. Delete or
clearly mark the prototype code as throwaway before Phase 3.

Skip this phase if no load-bearing uncertainty exists after Phase 1.

## Phase 3 — Convert to tracker items

Present the validated plan to the user and ask:

> "Should I create beads for this plan, or stop at the written design doc?"

**If beads:** use the `br` CLI conventions to create issues, set types/priorities, and
wire dependencies:

```bash
br create "..." --type feature --priority 2
br dep add <issue-id> <depends-on-id>
br sync --flush-only
git add .beads/ && git commit -m "chore(beads): ..."
```

Group work into logical epics → tasks → sub-tasks. Every bead needs: goal, why, current
state, next action, and an acceptance criterion that is testable at runtime (not just
"code exists").

**If no beads:** leave the finalized `DESIGN.md` / ADR as the deliverable and note the
file path in the session summary.

## Guardrails

- Never start implementation during `/design`. The output is a plan or beads, not code.
- If the user changes scope mid-grill, restart Phase 1 grill on the revised scope.
- Design docs that change after beads are created are stale — re-run Phase 3 on the delta.
