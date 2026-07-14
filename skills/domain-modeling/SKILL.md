---
name: domain-modeling
description: Build and sharpen a project's ubiquitous language — a CONTEXT.md glossary plus sparse ADRs — challenging terms against the glossary and cross-referencing code as you go. Use when pinning down domain terminology, recording an architectural decision, or when another skill needs to maintain the domain model.
when-to-use:
- pin down domain terminology, build a ubiquitous language / glossary, decode project jargon
- record an architectural decision (ADR)
- when a grilling or design session surfaces fuzzy or conflicting terms
allowed-tools:
- Bash
- Read
- Grep
- Glob
- Write
- Edit
category: docs
---

# Domain Modeling

Actively build and sharpen the project's domain model as you design. This is the *active* discipline — challenging terms, inventing edge-case scenarios, and writing the glossary and decisions down the moment they crystallise.

Merely *reading* `CONTEXT.md` for vocabulary is not this skill — that's a one-line habit any skill can do. This skill is for when you're **changing** the model, not just consuming it.

Why it matters: agents dropped into a project use 20 words where 1 will do because they don't share the team's jargon. A `CONTEXT.md` glossary is the shared, concise language that fixes this. Downstream: variables/functions/files get named consistently, the codebase gets easier to navigate, and the agent spends fewer tokens thinking because it has a tighter vocabulary. "There's a problem with the materialization cascade" beats a paragraph re-explaining it every session.

## File structure

Most repos have a single context:

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

If a `CONTEXT-MAP.md` exists at the root, the repo has multiple bounded contexts; the map points to where each `CONTEXT.md` lives and how the contexts relate. See [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md) for both shapes.

**Create files lazily** — only when you have something to write. No `CONTEXT.md` yet? Create it when the first term is resolved. No `docs/adr/`? Create it when the first ADR is needed.

## During the session

### Challenge against the glossary
When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately: "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"

### Sharpen fuzzy language
When the user uses vague or overloaded terms, propose a precise canonical term: "You're saying 'account' — do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios
Stress-test relationships with specific edge-case scenarios that force precision about the boundaries between concepts.

### Cross-reference with code
When the user states how something works, check whether the code agrees (Read/Grep). Surface contradictions: "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?"

### Update CONTEXT.md inline
When a term is resolved, update `CONTEXT.md` right there — don't batch. Use [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md). `CONTEXT.md` is a **glossary and nothing else**: totally devoid of implementation details. Not a spec, not a scratchpad, not a home for implementation decisions.

### Offer ADRs sparingly
Only offer an ADR when **all three** are true — (1) hard to reverse, (2) surprising without context, (3) the result of a real trade-off. If any is missing, skip it. Use [ADR-FORMAT.md](./ADR-FORMAT.md).

## Relationship to this repo's other artifacts

`CONTEXT.md` is **not** `AGENTS.md`. `AGENTS.md` (see [`agents-md`](../agents-md/SKILL.md)) holds behavioural guardrails — how agents should *act* in the repo. `CONTEXT.md` holds the *vocabulary* — what the words *mean*. They compose: an `AGENTS.md` can point at `CONTEXT.md` as the canonical glossary. Keep decisions-with-rationale in ADRs, guardrails in `AGENTS.md`, and pure terminology in `CONTEXT.md`.

## Related skills

- [`grilling`](../grilling/SKILL.md) — the interview loop that most often surfaces the terms this skill captures.
- [`agents-md`](../agents-md/SKILL.md) — behavioural guardrails, the sibling artifact.
