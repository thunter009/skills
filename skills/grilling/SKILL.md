---
name: grilling
description: Relentlessly interview the user about a plan or design, one question at a time, until every branch of the decision tree is resolved. Use before building anything non-trivial, or when the user says "grill me", "grill this", "interrogate this plan", or "stress-test this before I build".
when-to-use:
- grill me, grill this plan, interrogate this design, stress-test before building
- Before implementing a non-trivial change where the user hasn't pinned down every decision
- When alignment is fuzzy and you'd otherwise guess at intent
allowed-tools:
- Bash
- Read
- Grep
- Glob
- AskUserQuestion
category: pm
---

# Grilling

Interview the user relentlessly about every aspect of a plan or design until you reach a genuine shared understanding. Walk down each branch of the decision tree, resolving dependencies between decisions one at a time. This is the fix for the most common failure mode in agent work: **you thought you understood what they wanted, then built the wrong thing.**

## The loop

1. **One question at a time.** Ask a single question, give your **recommended answer**, and wait for the user's response before moving on. Asking multiple questions at once is bewildering and produces shallow answers.
2. **Walk the tree in dependency order.** Resolve the decisions that unlock other decisions first. When an answer opens new branches, follow them before returning to siblings.
3. **Look up facts; ask about decisions.** If a fact can be found by exploring the codebase (how something currently works, what a type is, whether a file exists), look it up with Read/Grep/Glob rather than asking. The *decisions* — the trade-offs only the user can make — are theirs; put each one to them and wait.
4. **Always recommend.** Every question carries your best answer and a one-line why. The user is confirming or overriding a proposal, not filling a blank.
5. **Don't build until confirmed.** Do not enact the plan until the user explicitly confirms you've reached a shared understanding. Reaching the end of the tree is not permission to start — say "I think we're aligned; ready to proceed?" and wait.

## Relationship to AskUserQuestion

This repo's default is `AskUserQuestion` for discrete forks (2–4 options, no deep dependency chain) — keep using it there. **Grilling is the other mode:** a sequential, conversational walk down a whole decision *tree* where later questions depend on earlier answers and the option set isn't knowable up front. Use grilling for shaping a spec or design end-to-end; use AskUserQuestion for the isolated pick. You may *fire* an AskUserQuestion mid-grill when a particular node happens to be a clean 2–4 way fork — but the spine of the session is the one-at-a-time interview.

## When the design touches domain language

If the grilling surfaces fuzzy or conflicting *terminology* — two words for one concept, an overloaded term, a term that contradicts the code — switch on the [`domain-modeling`](../domain-modeling/SKILL.md) discipline: sharpen the term and capture it in `CONTEXT.md` inline, then continue the grill. Alignment on *words* is half of alignment on *plans*.

## Related skills

- [`domain-modeling`](../domain-modeling/SKILL.md) — capture the shared language a grill surfaces.
- [`idea-wizard`](../idea-wizard/SKILL.md) / [`design`](../design/SKILL.md) — broader idea-funnel and fuzzy-to-build-ready flows that include an interview step of their own; grilling distils that step into a standalone loop.
- `decision-canvas` — when `ATRIUM=1` and the decision set exceeds a conversational grill (many questions needing evidence to judge).
