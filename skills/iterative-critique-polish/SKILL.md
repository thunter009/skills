---
name: iterative-critique-polish
description: >-
  Run any artifact (prose, plan, proposal, design doc, spec) through N adversarial
  critique-then-revise passes until it stops improving. Use when "polish this", "make
  this airtight", "tear this apart and rebuild it", or hardening a deliverable before it ships.
when-to-use:
- polish this, critique and improve, iterate on this draft, make this airtight
- 5x critique loop, refine until it stops improving, harden before shipping
- When a draft is "done" but you want adversarial passes to surface what you can't see
category: docs
related-skills:
- de-slopify
- multi-pass-bug-hunting
- multi-round-research
- polish-beads
---

<!-- TOC: Core | When To Use | THE EXACT PROMPT | The Loop | Pass Anatomy | Convergence | Dual-Model Variant | Artifact Types | Anti-Patterns | Related -->

# Iterative Critique / Polish Loop

> **Core Insight:** The first critique finds obvious flaws. The second finds flaws the
> obvious ones were hiding. The third catches what you broke fixing the first two. Quality
> comes from passes, not from one heroic edit. Stop when a pass yields nothing material — not at a fixed count.

This is the general-artifact sibling of code-specific `multi-pass-bug-hunting` and tracker-specific `polish-beads`. Use it on anything written: a proposal, a plan, a README, an essay, a spec, an architecture doc.

## When To Use

- A draft exists and reads "fine," but fine isn't the bar.
- Before a deliverable goes to a human who matters (exec, customer, reviewer).
- After a deep-investigation pass produces a proposal (pairs with [`multi-round-research`](../multi-round-research/SKILL.md)) — polish the proposal before acting on it.
- Not for: greenfield generation (nothing to critique yet), or trivial edits (one read fixes it).

## THE EXACT PROMPT

Paste this, filling the `{ARTIFACT}` and `{N}` (default 5):

```
You are running an iterative critique-and-polish loop on the artifact below.
Run up to {N} passes. Each pass has two strictly separated steps:

  1. CRITIQUE (adversarial, fresh eyes): Pretend you have never seen this and
     someone is paying you to find what's wrong. List concrete, specific defects
     — not vibes. For each: what's wrong, why it matters, and the fix direction.
     Cover: correctness/claims, structure/flow, gaps & unstated assumptions,
     precision of language, audience fit, and anything that would make a skeptic
     stop reading. Do NOT revise in this step.

  2. REVISE: Apply the fixes. Output the full improved artifact.

After each pass, state a one-line CONVERGENCE VERDICT:
  - "MATERIAL" if the pass changed substance, or
  - "COSMETIC" if only wording/polish remained.
Stop early the first time a pass is COSMETIC twice running, or you hit {N}.
Never invent new scope to justify another pass — polish what's there.

Artifact:
{ARTIFACT}
```

## The Loop

```
draft ──► [Pass 1: critique → revise] ──► [Pass 2 ...] ──► ... ──► converged
                  │                            │
            fresh-eyes critique          critique the REVISED text,
            of the ORIGINAL              not the original
```

Each pass critiques the **output of the previous pass**, not the original draft. That's what surfaces second- and third-order issues (an early fix that introduced a new gap).

## Pass Anatomy

| Step | Rule |
|------|------|
| Critique | Adversarial. Assume the artifact is wrong until proven right. Be specific — a defect names a location and a reason. |
| Separation | Never critique and revise in the same breath. Listing flaws first prevents motivated reasoning ("it's basically fine"). |
| Revise | Apply *all* the pass's findings, then re-emit the whole artifact so the next pass sees a clean target. |
| Verdict | MATERIAL vs COSMETIC. Two COSMETIC passes in a row = converged. |

Optionally rotate the **lens** per pass for diversity instead of repeating one critic: pass 1 correctness, pass 2 structure/flow, pass 3 audience/skeptic, pass 4 precision/concision, pass 5 final de-slop. This catches failure modes a single repeated critic is blind to.

## Convergence

Stop on the **first** of:
- Two consecutive COSMETIC passes (no substance left to change).
- `{N}` passes reached (hard cap; default 5).
- A pass proposes only new scope, not fixes — that's drift, not improvement; stop.

Do **not** keep going to hit a round number. Five is a ceiling, not a quota.

## Dual-Model Variant (cross-model grooming)

For high-stakes plans/specs, replace the single self-critic with **two independent high-effort reviewers from different model families** (e.g. a Claude subagent + `codex exec` at high/xhigh reasoning), then integrate. Proven shape (2026-07-21, a private data-platform repo's user-docs spec — each reviewer found real defects the other missed):

1. **One shared brief, run twice in parallel.** Same context bundle (the artifact + the docs/beads/code it must stay consistent with), same hard constraints (settled decisions listed as non-negotiable), same strict output format: a unified **git diff against the artifact** + a ranked rationale list. The diff format forces concrete, appliable proposals instead of essay-critique.
2. **Integrate as a skeptic, not a merger.** Before applying any hunk, **verify its factual claims against the codebase/source of truth** — reviewers confidently cite params, file paths, and behaviors that may be wrong (correspondence over coherence). Reject constraint-violating hunks outright.
3. **Publish a verdict ledger**: wholeheartedly agree / somewhat agree (applied modified) / disagree (rejected, with reason) — per proposal, in the final summary. This keeps the human able to audit your integration judgment cheaply.
4. **Then run the standard equilibrium loop** (this skill's main prompt) on the *integrated* artifact — integration itself introduces seam errors (era mismatches, half-applied renames, contradictory guardrails), and the passes after integration are where they surface.

Cost: ~2× a single review. Worth it when the artifact gates a build (spec, PRD, migration plan); skip for low-stakes prose.

## Artifact Types

Works on: proposals, plans, PRDs, READMEs, design docs, essays, emails, postmortems, ADRs. For each, the critique lens shifts (a PRD critique weighs acceptance-criteria completeness; an essay critique weighs argument and flow) — the loop structure is identical.

For a final-pass language cleanup, chain `de-slopify` (AI-writing artifacts) or the `humanizer` skill after convergence.

## Anti-Patterns

- **Critique + revise fused.** Skipping the explicit defect list lets the model rationalize the draft as good enough. Keep them separate.
- **Critiquing the original every pass.** Pass N must critique pass N−1's output, or you never reach second-order issues.
- **Fixed 5 passes regardless of convergence.** Burns tokens re-polishing a converged artifact and invites scope drift. Honor the COSMETIC×2 early-exit.
- **Scope creep disguised as polish.** "It would be even better if we also added X" is new work, not critique. Flag and stop.
- **Sycophantic critique.** "This is excellent, minor nit:" is not a critique. The prompt forces an adversarial stance for a reason.

## Related

- `multi-pass-bug-hunting` — same audit-fix-rescan philosophy, for code.
- `polish-beads` — iterative passes specialized to beads/Linear issues/plans.
- [`multi-round-research`](../multi-round-research/SKILL.md) — produces the proposal this loop then hardens.
- `de-slopify` — final-pass AI-writing cleanup.
