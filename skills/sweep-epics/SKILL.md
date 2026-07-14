---
name: sweep-epics
description: Close epics whose children are already done.
when-to-use:
- sweep epics, close completed epics, stale epics
- During backlog cleanup
permissions:
- read
- bash
category: pm
related-skills:
- audit-exit-conditions
---

# Sweep Epics — Auto-Close Completed Epics

Post-flight validation: finds open epics with all children closed and closes them. Also reports partially-complete epics so you can triage stragglers.

## Scope

- Scans all open epics
- Checks child task statuses
- Auto-closes fully-complete epics (with confirmation)
- Reports partial-completion percentages for the rest

Does NOT:
- Validate exit conditions (use `/audit-exit-conditions`)
- Create or modify child tasks
- Touch non-epic beads

## Arguments

- No args: sweep ALL open epics
- Epic ID(s): check specific epics (e.g., `bd-38dj bd-3kbq`)
- `--auto`: close fully-complete epics without asking (default: confirm first)

---

## Execution Steps

### 1. Discover Open Epics

```bash
br list --status=open --type=epic
```

If specific epic IDs were provided as arguments, filter to just those.

### 2. Check Children for Each Epic

Child discovery in beads uses THREE mechanisms (all must be checked):

```bash
# Method A: Explicit parent-child deps from br show
br show <epic-id>
# Parse the Dependents: section for parent-child relationships

# Method B: Dot-notation children (implicit convention)
# Children of epic "bd-1l2w" have IDs like "bd-1l2w.1", "bd-1l2w.2", etc.
br list --status=open 2>/dev/null | grep "^<epic-id>\."

# Method C: blocks-edges ON the epic (epic blocked-by its children)
br show <epic-id>
# Parse the Dependencies: section for `-> <id> (blocks)` lines — each is a
# CANDIDATE child; apply the child-vs-prerequisite test below before counting.
```

**IMPORTANT:** `br list --format json` does NOT include the `dependents` field. `br list --parent` may return empty. Always use `br show <epic-id>` for explicit deps AND grep for dot-notation children.

**IMPORTANT (Method C):** some epics encode children ONLY as `Dependencies: -> bd-X (blocks)` on the epic itself — the Dependents section is empty and the child IDs are not dot-notation (2026-06-22 sweep: bd-836 and bd-jur were both misreported as "empty epics" this way, nearly triggering the stale-close suggestion on epics with live children). Never declare an epic empty until Method C has also been parsed.

**Method C child-vs-prerequisite test (mandatory):** `-> <id> (blocks)` is a *generic* dependency edge — epics also use it for cross-epic/shared prerequisites, and counting those as children corrupts `total`/`pct` (a false `pct==100` feeds the `--force` close in Step 5). For each candidate id, run `br show <id>` and classify:
- **Prerequisite (exclude)** if the target is itself `type=epic`, OR its Dependents section lists beads/epics *other than this epic* (a shared prereq consumed by multiple parents).
- **Child (include)** if this epic is the target's only dependent, especially when the title carries the epic's family prefix (e.g. `maintainer.4:` under the repo-maintainer epic, `scorecard.3:` under the scorecard epic).
- **Ambiguous** (sole dependent but reads like a standalone project): do not count it silently — list it in the report under "unclassified blocks-edges" for the operator to resolve.

For each child found (from any method), check if it's CLOSED or OPEN.

Compute:
- `total`: number of children (union of all three methods, deduplicated)
- `closed`: number of closed children
- `open`: number of open children
- `pct`: `int(closed / total * 100)` — use integer truncation, not rounding (e.g., 2/3 = 66, not 67 or 70)

**IMPORTANT:** Check `total` FIRST. If `total == 0` (after Methods A, B, AND C), the epic is **empty** — skip percentage calculation entirely.

### 3. Categorize Results

Apply these rules **in order** (first match wins):

1. **Empty (`total == 0`):** Epic has no child tasks. If created >30 days ago, suggest closing as stale. If <30 days, suggest task breakdown. Status: `empty`.
2. **Fully complete (`pct == 100`):** All children closed — ready to auto-close. Status: `ready_to_close`.
3. **Nearly complete (`pct > 50`):** Over half done — list remaining open children with their titles so user can decide. Status: `nearly_complete`.
4. **In progress (`pct <= 50`):** Just report the percentage, don't suggest closing. Status: `in_progress`.

### 4. Report

```markdown
## Epic Sweep Report

**Scanned:** N open epics
**Fully complete:** N (ready to close)
**Nearly complete:** N (>50%)
**In progress:** N
**Empty (no children):** N

### Ready to Close

| Epic | Title | Children | Status |
|------|-------|----------|--------|
| bd-38dj | Security Audit | 12/12 (100%) | ✅ Close |

### Nearly Complete

| Epic | Title | Progress | Remaining |
|------|-------|----------|-----------|
| bd-3kbq | First Extraction in 2 Min | 6/7 (86%) | bd-3kbq.3: Auto-classification on upload |

### In Progress

| Epic | Title | Progress |
|------|-------|----------|
| bd-1l3 | Stripe Billing | 2/6 (33%) |

### Empty Epics (no children)

| Epic | Title | Action Needed |
|------|-------|---------------|
| bd-xxxx | Some Epic | Needs task breakdown or close |

### Unclassified Blocks-Edges

| Epic | Candidate | Why ambiguous |
|------|-----------|---------------|
| bd-xxxx | bd-yyyy | Sole dependent but reads like a standalone project |
```

(Omit the Unclassified Blocks-Edges section when Step 2's Method C test left no ambiguous candidates.)

### 5. Close Fully-Complete Epics

For each 100% epic:
- If `--auto` flag: close immediately
- Otherwise: present the list and ask user to confirm

Close with:
```bash
# Use --force to bypass stale bd- prefix deps that may block closure
br close <epic-id> --force --reason "all N children complete"
```

**Note:** Stale `bd-` prefix dependency references from the beads migration can block `br close`. The `--force` flag bypasses these. The open-children guard (added to beads_rust) prevents accidental premature closure of epics that actually have open children.

### 6. Prompt for Nearly-Complete

For each >=80% epic, ask:
- "Close remaining tasks and epic?"
- "Leave open?"
- "Close epic anyway (remaining tasks are out of scope)?"

### 7. Sync

After any closures:
```bash
# Use --force if dirty flags were already cleared (e.g., after ralph-tui run)
br sync --flush-only --force
```

Remind user to `git add .beads/ && git commit -m "chore: sweep completed epics"` if any changes were made.

## Ghost Epic Check

For >=80% epics, do a quick sanity check before closing — beads can be open when code is shipped (ghost beads):

```bash
# Check if the remaining open child's deliverable actually exists
git log --oneline -5 -- '*<keyword>*'
```

If the code for a remaining child exists and tests pass, the child is a ghost bead — close it too, then close the epic.
