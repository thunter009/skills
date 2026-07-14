---
name: refine-skill
description: Mine CASS sessions and rewrite a skill based on real usage.
when-to-use:
- refine skill, improve skill, skill usage patterns
- When a skill underperforms in practice
user_invocable: true
category: meta
projects:
- agent-skills
---

Recursively improve a skill using real session data from CASS.

**Target skill:** $ARGUMENTS

**Step 1 — Mine CASS for usage sessions:**
```bash
cass search "$ARGUMENTS" --robot --limit 100 --fields minimal
```

Look for:
- **Clarifying questions**: where agents asked "do you mean X or Y?" — the skill was ambiguous
- **Repeated mistakes across sessions**: systematic gap in instructions
- **Creative workarounds**: agents inventing their own approach — skill is missing a useful pattern
- **Outright failures**: skill directed agents to do something wrong or impossible
- **Confusion about flags/options**: tool interface needs better docs in the skill

**Step 2 — Read the current skill:**
Find and read the SKILL.md file for the target skill.

**Step 3 — Analyze the gap:**
Compare what the skill instructs vs. what agents actually did. List every discrepancy.

**Step 4 — Rewrite the skill:**
Fix every issue found. Make the happy path obvious. Add guardrails for common mistakes. Incorporate the best workarounds as official steps. Don't remove working patterns — extend and clarify.

**Step 5 — Validate:**
Run the skill's Tier 1 validation if available. Ensure the rewrite doesn't break the SKILL.md format.

Report: sessions analyzed, patterns found, changes made, before/after diff summary.
