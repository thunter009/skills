---
name: reality-check
description: Check whether a swarm is busy but not converging on the goal.
when-to-use:
- reality check, are we on track, strategic review
- During long swarm sessions
permissions:
- read
- bash
category: pm
---

# /reality-check

Strategic drift detection. Is the swarm converging on the actual goal?

**Scope:** $ARGUMENTS (if empty, assess the whole project)

## Step 1: Understand the Goal

Read AGENTS.md, README, and any markdown plan files to understand what this project is supposed to be and do. Summarize the goal in 2-3 sentences.

## Step 2: Assess Current State

```bash
br list --status open --json 2>/dev/null
br list --status in_progress --json 2>/dev/null
br list --status closed --json 2>/dev/null | wc -l
bv --robot-triage 2>/dev/null | head -60
git log --oneline -20
```

Answer these questions:
1. **Where are we?** What percentage of the vision is actually implemented and working?
2. **What's stuck?** Any beads in_progress for too long? Any with no recent commits?
3. **What's the gap?** If we intelligently implement ALL open + in_progress beads, would we close the gap completely?
4. **What's missing?** Are there aspects of the goal that have NO corresponding beads at all?

## Step 3: Diagnose Drift

Check for these drift patterns:

| Pattern | Signal |
|---------|--------|
| **Busy but far** | Many closed beads, but core goal still not met |
| **Scope creep** | Open beads include work that wasn't in the original vision |
| **Foundation gap** | Lots of feature beads but missing infrastructure/testing |
| **Orphan work** | Closed beads that don't contribute to any user-visible outcome |
| **Dependency deadlock** | Circular or stalled dependency chains blocking progress |
| **Process porn** | Activity is receipts/certificates/gate-reports/meta-audits, not capability — hand off to `just-say-no-to-process-porn-and-ceremony` |

## Step 4: Report

Present findings as:

### Status
- Goal: [2-3 sentence summary]
- Progress: [X/Y beads closed, estimated % toward goal]
- Trajectory: [On track / Drifting / Stalled]

### Gap Analysis
- What's working and shipping
- What's missing entirely (no beads exist)
- What's stuck (beads exist but blocked/stalled)

### Recommendation
One of:
- **Continue** — swarm is on track, keep executing
- **Revise beads** — create/modify beads to close identified gaps
- **Pause and replan** — drift is significant enough to warrant returning to plan space

If recommending bead revisions, list the specific beads to create or modify.

## Anti-patterns
- Confusing "lots of commits" with "making progress toward the goal"
- Treating bead count as a proxy for completion
- Ignoring missing beads (things not tracked can't converge)
