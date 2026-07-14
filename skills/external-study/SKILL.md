---
name: external-study
description: Study an external project and adapt its best ideas to this repo.
when-to-use:
- study this project, research this repo, reimagine this tool
- When borrowing concepts rather than code
permissions:
- read
- bash
category: pm
---

# /external-study

Research an external project and reimagine its ideas for this project.

**Arguments:** $ARGUMENTS — expects a repo URL or project name to study.

## Prerequisites

You must already understand the current project's architecture, primitives, and unique value. Read AGENTS.md and explore the codebase first if you haven't already.

**Context budget:** This is a heavy skill. Steps 1-6 can exhaust a context window on large external projects. If the external repo is large, focus investigation on its core architecture (README, main entry points, key abstractions) rather than reading every file. If context runs low, stop at the current step, present what you have, and let the user continue in a fresh session.

## Step 1: Investigate and Propose

Clone the external project to `/tmp/` and investigate it thoroughly.

```bash
git clone --depth 1 "<repo-url-from-arguments>" /tmp/external-study-target 2>/dev/null
```

Study its architecture, design patterns, and key innovations. Look for ideas that could be reimagined on top of this project's existing primitives in highly accretive ways.

Write a proposal document: `PROPOSAL_TO_INTEGRATE_IDEAS_FROM_<EXTERNAL>_INTO_<PROJECT>.md`

Focus on leveraging the special concepts and value-add from BOTH projects to create something genuinely novel — not a shallow port.

## Step 2: Iterative Deepening

The first draft is always too conservative. Push for depth:
- Go deeper into the external project's architecture
- Think more ambitiously about what combinations are possible
- Look for ideas that are "radically innovative" because they combine capabilities neither project has alone

Revise the proposal with bolder, more compelling integrations.

## Step 3: Inversion Analysis

Invert the analysis: what can THIS project do — because of its unique primitives and capabilities — that the external project fundamentally cannot, even if they wanted to?

This surfaces the highest-value integration points: capabilities that are genuinely novel rather than reimplementations.

Add these inverted insights to the proposal.

## Step 4: Blunder Hunt (5 passes)

Run this critique pass **5 times consecutively**, maintaining a running tally:

> Look over everything in the proposal for blunders, mistakes, misconceptions, logical flaws, errors of omission, oversights, sloppy thinking, etc.

After each pass, log: `Pass N: found X issues, fixed Y`. Then immediately start the next pass on the revised text. Do NOT stop early because a pass found fewer issues. Complete all 5 passes.

Each pass finds things the previous pass missed. Models tend to find 15-20 issues on the first pass and declare satisfaction. Repeating forces past the "reasonable number" ceiling.

## Step 5: Close Design Gaps

After blunder hunts, identify items flagged as needing follow-on design work. Address them explicitly with concrete design decisions rather than leaving them vague.

Revise the proposal to close every identified gap.

## Step 6: Self-Contained Background

Add comprehensive background sections so the proposal can stand alone:
- What this project is, how it works, what makes it compelling
- What the external project is, how it works, what makes it compelling
- Why the combination creates unique value

This makes the proposal useful for cross-model review or sharing with collaborators who lack session context.

## Step 7: Present and Plan

Present the final proposal to the user with:
- Executive summary of the strongest integration ideas
- Architectural innovations that leverage both projects' strengths
- Recommended next steps (convert to beads via standard pipeline)
- Open questions that need human judgment

**Ask the user** whether to proceed to bead creation for selected ideas.

## Cleanup

Remove the cloned repo when done (confirm with user if the proposal references specific files they may want to keep):

```bash
[ -d /tmp/external-study-target ] && rm -r /tmp/external-study-target
```

## Anti-patterns
- Shallow porting (copying features without reimagining them)
- Conservative first drafts accepted without deepening
- Skipping the inversion analysis (misses the highest-value ideas)
- Running blunder hunt only once (leaves subtle flaws)
