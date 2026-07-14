---
name: groom
description: Surface the next best task across beads, Linear, PRs, Todoist, and git.
when-to-use:
- what should I work on, what's next, groom
- At session start or backlog review
permissions:
- read
- bash
category: pm
---

# /groom

Surface what to work on next. Aggregates open work across beads, Linear, GitHub PRs, Todoist, and local git state into prioritized buckets.

## Mode

Default is **report mode** (read-only). After presenting the report, offer: "Want me to act on any of these? (close ghost beads, sweep done epics, reprioritize)"

When the user says yes, transition to **action mode** — close beads, update priorities, sweep epics, etc. This matches real usage: every grooming session immediately mutates state after the report.

## Arguments

| Flag | Default | Description |
|------|---------|-------------|
| `--prs-only` | false | Show only GitHub PR status |
| `--linear-only` | false | Show only Linear issues |
| `--beads-only` | false | Show only beads |
| `--stale N` | 7 | Days of inactivity to flag as stale |

## Prerequisites

- `br` CLI (for beads) — optional
- `bv` CLI (for graph-aware triage) — preferred over `br` for prioritization
- `linear` CLI (for Linear issues) — optional
- `gh` CLI (for GitHub PRs) — optional
- `td` CLI (for Todoist tasks) — optional

## Workflow

### 1. Detect Project Context

```bash
git remote get-url origin 2>/dev/null
ls .beads/ 2>/dev/null
linear team list 2>/dev/null | head -3
td auth status 2>/dev/null
```

Also check for recent meetings that might contain action items:
```bash
# If Granola MCP available, check last 3 days
# Meeting action items often affect priorities
```

### 2. Gather State (in parallel)

Run all applicable sources concurrently. Skip sources that aren't available.

```bash
# Beads — prefer bv for graph-aware ranking
if command -v bv >/dev/null 2>&1; then
  bv --robot-triage --format toon
fi
if command -v br >/dev/null 2>&1; then
  br list --status=open
  br list --status=open --type=epic
fi

# Linear (state values: started/unstarted/backlog — NOT "In Progress")
if command -v linear >/dev/null 2>&1; then
  linear issue list --state started --state unstarted --state backlog --limit 50
fi

# GitHub PRs
if command -v gh >/dev/null 2>&1; then
  gh pr list --state open --json number,title,reviewDecision,statusCheckRollup,updatedAt
fi

# Todoist — project-scoped if possible, otherwise overdue/today
if command -v td >/dev/null 2>&1; then
  project_name="$(basename "$PWD")"
  if td project list 2>/dev/null | grep -Fqx "$project_name"; then
    td task list --project "$project_name"
  else
    td today
  fi
fi

# Local git
git status --short
git log --oneline -10
```

### 3. Ghost Detection

Before categorizing, check for **ghost beads** — issues marked open but already implemented:

For each open bead, quick-check if the work might be done:
```bash
# Check if files mentioned in the bead exist and have recent commits
git log --all --oneline -3 -- '*<keyword>*'
```

If a bead's expected outputs exist and tests pass, flag it as **"likely done — verify and close"**. In past audits, up to 69% of open backlogs were phantom work.

### 4. Categorize into Priority Buckets

If `bv --robot-triage` was available, use its PageRank/betweenness scores for bead ordering. Otherwise, fall back to manual bucketing:

#### P0 — Needs Attention Now
- PRs with failing checks (`statusCheckRollup` contains failure)
- PRs with changes requested
- PRs approved but not merged (ready to ship)
- Ghost beads (likely done, just need closing)

#### P1 — In Progress
- Linear issues in started state
- Beads with recent commits (cross-ref `git log`)
- PRs with pending reviews

#### P2 — Nearly Done
- Epics with >75% children closed (show percentage)
- Linear issues in review state
- Closed epics with open children (data integrity issue — flag for sweep)

#### P3 — Ready to Pick Up
- High-priority unstarted Linear issues (priority 1-2)
- Unblocked backlog beads (from `bv` ranking or `br ready`)
- Stale PRs that need a nudge
- Overdue Todoist tasks

#### Flags
- **Stale:** started items with no activity in `--stale N` days
- **Orphan:** beads with no matching Linear issue, or vice versa
- **Closed parent, open children:** epics marked done but children still open
- **Ghost:** open issues where implementation appears complete
- **Stale PRD:** PRDs under `docs/product/` or `docs/archive/` with `last_audited:` > 90 days (drift between claimed status and reality)

### 5. Cross-Reference

Check for orphans and integrity issues:
- Beads without a Linear issue URL in metadata
- Linear issues without a linked bead or PR
- PRs without a linked Linear issue in description
- Closed epics with open children (use `br list --type=epic --status=closed` then check children)

**PRD staleness** (only if `docs/product/` exists):
```bash
# Find PRDs with last_audited: > 90 days old
if [ -d docs/product ] || [ -d docs/archive ]; then
  cutoff=$(date -v-90d +%Y-%m-%d 2>/dev/null || date -d '90 days ago' +%Y-%m-%d)
  grep -rHE "^last_audited: *[0-9]{4}-[0-9]{2}-[0-9]{2}" docs/product docs/archive 2>/dev/null \
    | awk -F'last_audited: *' -v cutoff="$cutoff" '$2 < cutoff { print $0 }'
fi
```

Surface each hit as a **Stale PRD** flag. Age > 90d is the trigger; > 120d is the escalation. Recommend the user run the `audit-prds` prompt (see `prompts/audit-prds.md`) to re-verify.

### 6. Present Report

Output markdown tables per bucket:

```
## P0 — Needs Attention Now (2)

| Source | ID | Title | Status | Last Activity |
|--------|----|-------|--------|---------------|
| PR | #42 | Fix auth timeout | Changes requested | 2d ago |
| Bead | f4j.3 | Add search | Ghost — tests pass | 8d ago |

## P1 — In Progress (3)
...

## Flags (4)

| Type | ID | Title | Detail |
|------|----|-------|--------|
| Stale | ABC-123 | Refactor auth | No activity 12d |
| Orphan | bead-7f3 | CLI redesign | No Linear issue |
| Closed parent | epic-2we | Calendar | 2 of 5 children still open |
```

If no items in a bucket, omit that section.

### 7. Suggest Next Action

End with a single recommended next action:

```
**Suggested:** Close 3 ghost beads (f4j.3, f4j.5, sa2s.2) then address PR #42 review feedback
```

Pick the highest-priority item the user can act on immediately.

## Guidance

- Prefer items the user is assigned to / authored
- When multiple P0 items exist, order by staleness (oldest first)
- Keep tables compact — truncate long titles at 60 chars
- Show item counts in section headers: `## P1 — In Progress (3)`
- **Linear CLI note:** state values are `started`/`unstarted`/`backlog` (not "In Progress"). No `--mine` flag (default shows your issues). Use `-A` for all assignees. No `--cycle` flag — use GraphQL for sprint queries
