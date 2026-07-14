---
name: idea-wizard
description: Run a structured idea funnel to generate and rank project improvements.
when-to-use:
- brainstorm, idea wizard, what should we build next
- When exploring new features
permissions:
- read
- bash
category: pm
related-skills:
- polish-beads
---

# /idea-wizard

Structured brainstorming funnel for existing projects. Produces polished beads from the best ideas.

**Target:** $ARGUMENTS (if empty, target the current project)

## Step 1: Ground in Reality

Read AGENTS.md/CLAUDE.md and understand the project's purpose, architecture, and current state.

```bash
br list --json 2>/dev/null | head -100
```

List all existing beads to avoid proposing duplicates.

## Step 2: Generate 30, Winnow to 5

Generate 30 ideas for improvements, enhancements, new features, or fixes. Consider:
- User pain points and workflow friction
- Missing features that similar tools have
- Performance or reliability improvements
- Developer experience improvements
- Security hardening opportunities
- Integration opportunities

Then self-select the **very best 5** and explain why each is valuable. Be ruthlessly critical — winnowing forces evaluation that asking for 5 directly does not.

For each of the 5, explain:
- What it does and why users would care
- How it fits with existing architecture
- Whether it conflicts with or duplicates any existing beads
- Rough complexity estimate (S/M/L)

**Present the top 5 to the user. Wait for feedback before continuing.**

## Step 3: Expand to 15

After user acknowledges the first 5, produce the next best 10 ideas (ideas 6-15). For each:
- Check against existing beads for novelty
- Explain the value proposition
- Note any dependencies on the top 5

**Present all 15 to the user. Ask which to pursue.**

## Step 4: Convert to Beads

For each selected idea, create beads using `br`:
- Rich descriptions with rationale, not terse bullet points
- Dependencies between the new beads and existing work
- Priority levels reflecting user's indicated preferences
- Testing obligations embedded in each bead

```bash
br create --title "..." --priority N --label "..." --type feature
```

## Step 5: Polish 4-5x

Run bead polishing passes. Each pass:
1. Review each new bead — does it make sense? Is it optimal? Could we improve it?
2. Check for duplicates or excessive overlap with existing beads
3. Verify dependency graph is correct
4. Ensure test obligations are explicit

Do 1-2 passes here. For deeper polishing (4-5+ passes, fresh sessions), hand off to `/polish-beads` afterward.

**DO NOT OVERSIMPLIFY. DO NOT LOSE FEATURES OR FUNCTIONALITY between passes.**

## Output Format

After polishing, present a summary:
- Beads created (with IDs)
- Dependency graph overview
- Recommended implementation order (from `bv --robot-triage` if available)
- Ideas that were generated but not selected (for future reference)
