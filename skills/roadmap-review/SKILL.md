---
name: roadmap-review
description: Review and sync roadmap docs against tracker reality.
when-to-use:
- sync roadmap, review roadmap, roadmap drift
- When roadmap.md may be stale
permissions:
- read
- bash
- edit
category: docs
related-skills:
- roadmap-docs
---

# Roadmap Sync

Syncs state between three sources: **issue tracker** (Linear, beads, or GitHub Issues), **roadmap.md** (quarterly grid), and **repo files** (`projects/*.md`, `initiatives/*.md`).

## Arguments

| Flag | Default | Description |
|------|---------|-------------|
| `--auto` | false | Apply safe changes without confirmation (nightshift mode) |
| `--report-only` | false | Detect drift only, no changes |
| `--include-html` | false | Also update HTML roadmap artifacts if present |

Default mode is interactive (confirm each change).

## Issue Tracker Detection

Auto-detect the project's tracker before starting:

| Signal | Tracker |
|---|---|
| `linear` CLI available + Linear URLs in project files | **Linear** |
| `.beads/` dir or `beads.toml` present | **beads** |
| `.github/` dir + GitHub issue URLs in project files | **GitHub Issues** |
| `linear_projects.json` or similar data file | **Offline Linear** (file-based) |

If ambiguous, ask the user. All tracker-specific commands below show Linear examples — adapt for the detected tracker.

## Sync Modes

When the user triggers a sync, determine which mode from their request:

| Trigger phrases | Mode |
|---|---|
| "pull from tracker", "update roadmap from Linear", "sync down" | `pull` — Tracker → Local |
| "push to tracker", "update Linear from roadmap", "sync up" | `push` — Local → Tracker |
| "sync", "sync roadmap", "review roadmap", "full sync", "bidirectional" | `sync` — Bidirectional |

If ambiguous, ask the user which mode.

---

## Issue Counting Rules

**CRITICAL — getting this wrong corrupts roadmap data (happened in 9+ project counts):**

- **Done count:** `state.type == 'completed'` ONLY. Never include `canceled`.
- **Total count:** Exclude `canceled` from denominator too. Total = all non-canceled issues.
- **Progress fraction:** `completed / (total - canceled)`
- **Blocked items** are a separate KPI bucket — not part of Backlog count.

```graphql
# Correct Linear query for progress counts
{ project(id: "ID") { issues { nodes { state { type } } } } }
# Filter: completed = state.type == "completed", canceled = state.type == "canceled"
# Done = count(completed), Total = count(all) - count(canceled)
```

## Completion Date Rules

**Never fabricate dates.** Never trust project-level `completedAt` blindly.

- **Prefer:** last `completedAt` on non-canceled child issues
- **Detect batch-close patterns:** multiple issues closed at same minute = backlog cleanup, not real ship date
- **Fall back to:** project file `Completed` field if present
- **If unknown:** leave blank rather than guessing

## Health Status

Linear health values (`onTrack` / `atRisk` / `offTrack`) should be included in pull/push sync. Add to writable fields in project files.

---

## Mode 1: `pull` — Tracker → Local

Tracker is source of truth. Update local files to match.

### Steps

1. **Collect from tracker:**
   - All non-Idea projects with status, priority, lead, health, dates, initiative
   - All initiatives with linked project counts
   - Per-project issues if needed for progress counts

   ```bash
   # Linear examples
   linear project list --all-teams
   linear initiative list
   linear api '{ project(id: "ID") { issues { nodes { title state { name type } priority } } } }'

   # beads examples
   br list --status open
   br list --type epic
   ```

2. **Collect from local:**
   - Read `roadmap.md` — grid rows, Active Work, Backlog sections
   - Read all `projects/*.md` — Status, Priority, Lead, Initiative, Timeline
   - Read all `initiatives/*.md` — Status, Linked Projects

3. **Diff and apply:**

   **Roadmap grid (`roadmap.md`):**
   - Status emoji drift: update to match tracker (Completed→✅, In Progress→🚧, Paused→⏸, Canceled→remove)
   - Missing rows: add projects that are In Progress/Shaping/Ready with High+ priority
   - Stale rows: flag items whose tracker project is Completed/Canceled
   - Quarter assignments: derive from project Timeline fields

   **Project files (`projects/*.md`):**
   - Update Status, Priority, Lead, Timeline from tracker
   - Create missing files using `templates/project.md` format
   - Move completed projects to `projects/completed/`

   **Initiative files (`initiatives/*.md`):**
   - Update Linked Projects lists — add missing, convert plain text to relative links where repo files exist
   - Update Status from tracker

4. **Present changes to user for approval before writing.**

5. **Apply and commit** (see Commit section).

---

## Mode 2: `push` — Local → Tracker

Local repo is source of truth. Update tracker to match.

### Writable Fields

| Local Source | Tracker Target | How (Linear) | How (beads) |
|---|---|---|---|
| `projects/*.md` Status | Project status | `projectUpdate` with `state`/`statusId` | `br update --status` |
| `projects/*.md` Priority | Project priority | `projectUpdate` with `priority` (1-4) | `br update --priority` |
| `projects/*.md` Lead | Project lead | `projectUpdate` with `leadId` | `br update --assignee` |
| `projects/*.md` Timeline | Project dates | `projectUpdate` with `startDate`/`targetDate` | `br update --due` |
| `projects/*.md` Initiative | Initiative linkage | `initiativeToProjectCreate` | `br dep add` |
| `projects/*.md` Goal | Project description | `projectUpdate` with `description`/`content` | `br update --description` |
| `roadmap.md` emoji | Project status | Map ✅→Completed, 🚧→In Progress, ⏸→Paused, 🗓→Shaping/Discovery/Ready | Same mapping |

### Steps

1. **Collect from local** — read all `projects/*.md`, `initiatives/*.md`, `roadmap.md`
2. **Collect from tracker** — list all projects and initiatives
3. **Diff** — build change list: `[project, field, local_value, tracker_value, action]`
4. **Present change list:**
   ```
   | Project | Field | Local | Tracker | Action |
   |---------|-------|-------|---------|--------|
   | Comps Engine | Status | In Progress | Shaping | Push → In Progress |
   | Auth | Priority | High | Medium | Push → High |
   ```
5. **After approval, execute updates via tracker CLI/API.**
6. **Commit** any local file changes made during the process.

---

## Mode 3: `sync` — Bidirectional

Detect drift in both directions. Present conflicts for user resolution.

### Steps

1. **Collect from all three sources** (same as pull steps 1+2).

2. **Build unified diff table** — for each item in any source, compare:
   - Status (tracker vs roadmap emoji vs repo file)
   - Priority, Lead, Timeline (tracker vs repo file)
   - Presence (exists in tracker but not roadmap? on roadmap but not in tracker?)
   - Initiative linkage (tracker vs repo file vs initiative file)

3. **Classify each difference:**

   | Category | Description |
   |---|---|
   | **Agreement** | All sources match — no action |
   | **Tracker-only change** | Tracker differs from both local sources — suggest pull |
   | **Local-only change** | Local differs from tracker — suggest push |
   | **Conflict** | Tracker and local both changed differently — ask user |
   | **Missing** | Item exists in one source but not others — suggest create |
   | **Stale** | Item completed/canceled in one source, still active in another |

4. **Present findings organized by category:**

   ```
   ## Sync Report

   ### Conflicts (need your input)
   | Item | Field | Tracker | Local | Your call? |

   ### Pull (Tracker → Local)
   | Item | Field | Tracker | Local | Action |

   ### Push (Local → Tracker)
   | Item | Field | Local | Tracker | Action |

   ### Missing Items
   | Item | Present In | Missing From | Action |

   ### Stale Items
   | Item | Issue | Suggested Action |
   ```

5. **Classify each change by controversy level:**

   **Safe (auto-apply OK):**
   - Status emoji updates (tracker status → roadmap emoji)
   - Date range updates from tracker milestones
   - Issue/task count updates
   - Fix typos in project names (match tracker canonical name)

   **Moderate (auto-apply with commit comment):**
   - Add missing in-progress project as new roadmap row
   - Update quarter assignment when tracker dates clearly indicate shift
   - Add tracker URL to existing roadmap row

   **Controversial (never auto-apply):**
   - Remove roadmap rows
   - Create new tracker projects from roadmap-only items
   - Change quarter assignments without clear date evidence
   - Merge or split roadmap rows
   - Archive or cancel items
   - Conflict: tracker and local both changed differently

6. **Apply per mode:**

   **`--report-only`:** Stop after presenting drift report.

   **Interactive (default):**
   - Auto-apply all Safe changes
   - Present each Moderate change for confirmation
   - Present each Controversial change for confirmation
   - For conflicts, ask user which side wins. Do NOT auto-resolve.

   **`--auto` (nightshift):**
   - Apply all Safe changes
   - Apply Moderate changes with a note in commit message
   - Skip Controversial changes (log for human review)
   - Commit: `chore(roadmap): auto-sync — N status updates, M new rows`

7. **Post-sync verification:** Re-run drift detection to confirm remaining issues. Report: "N items synced, M items remaining (all controversial)".

8. **Commit** (see Commit section).

---

## Shared: Cross-Reference Checks

Run these regardless of mode:

### Status Drift
| Tracker Status | Expected Roadmap | Expected Repo File | Expected HTML |
|---|---|---|---|
| Completed | ✅ | Completed (move to completed/) | `done` → "Completed" |
| In Progress / Started | 🚧 | In Progress | `progress` → "In Progress" |
| Maintenance | 🚧 | Maintenance | `maintenance` → "Maintenance" |
| Ready | 🗓 | Ready | `ready` → "Ready" |
| Paused | ⏸ | Paused | `paused` → "Paused" |
| Blocked | ⛔ | Blocked | `blocked` → "Blocked" |
| Canceled | Remove or note | Remove or note | Remove |
| Shaping | 🗓 | Shaping | `shaping` → "Shaping" |
| Discovery | 🗓 or absent | Discovery | `discovery` → "Discovery" |
| Backlog | 🗓 or absent | Backlog | `planned` → "Planned" |

### Missing from Roadmap
Projects in tracker (non-Idea, non-completed, non-canceled) with no roadmap row. Prioritize:
1. **In Progress / Started** — should be on roadmap
2. **Shaping / Discovery / Ready with High+ priority** — likely belong
3. **Maintenance projects** — flag for user decision

Also check: projects in `projects/*.md` that have no roadmap row.

**Completed project exclusion:** Projects in `projects/completed/` with a `Completed` date before the current roadmap year are intentionally excluded from the grid. Do NOT flag these as missing. The `Completed` field in the project file is authoritative — tracker closure dates may reflect backlog cleanup rather than actual ship dates.

### Missing from Tracker
Roadmap items (especially 🚧) with no tracker project URL. Need either:
- A new tracker project created
- Linking to an existing project
- Confirmation they're tracked as issues only

### Stale Entries
- Items marked current-quarter that have slipped (check Timeline)
- Roadmap items with no matching project file AND no tracker project
- Completed items still in Active Work without ✅

### Absorbed / Duplicate Rows
Roadmap rows that are sub-items of a tracker project. Verify the sub-item exists as an issue in the parent project before merging.

### Initiative Coverage
- Initiatives with linked projects not on roadmap grid
- Orphan roadmap entries not linked to any initiative
- Plain-text project references in initiative files that should be relative links

---

## HTML Artifact Sync

If the project has HTML roadmap output (generated by the `roadmap-docs` skill), also sync those artifacts during `pull` and `sync` modes.

### Incremental Patch (data changes only)

When status, priority, progress, or descriptions change but no structural changes:

1. **JS data objects** (`const E={...}`, `const I=[...]`) — update all fields to match tracker state
2. **KPI counters** — recompute from updated data
3. **Gantt bars** — update CSS class to match status, recalculate `left`/`width` from dates
4. **Backlog table** — update `data-status`/`data-pr` attributes and badge classes
5. **Initiative cards** — update feature status classes and progress bars
6. **Epic detail page** — update status badges, child issue lists, progress bars
7. **Blocker annotations** — add/remove `blockedBy` in data + `epic-blocked` classes
8. **Header/footer dates** — update to reflect sync date
9. **Validate** — ensure all `data-epic`/`data-epics` refs have matching `E` entries

### Full Regeneration (structural changes)

For structural changes (epics added/removed, categories reorganized, initiative cards added/removed, Gantt rows reordered), incremental patching is insufficient. Instead:
1. Complete the sync (all steps above)
2. Invoke the `roadmap-docs --update` skill to regenerate HTML from scratch
3. The docs skill reads existing HTML + local data files and rebuilds all pages

**Status vocabulary must match across all views.** HTML keys: `done`=Completed, `progress`=In Progress, `ready`=Ready, `maintenance`=Maintenance, `planned`=Planned, `shaping`=Shaping, `discovery`=Discovery, `paused`=Paused, `blocked`=Blocked. Never use "Shipped" — canonical label is "Completed". Backlog projects must use their actual tracker status (`shaping`/`discovery`/`ready`/`paused`) not the grouped `planned` label.

---

## Commit

Split changes into atomic commits:
1. `fix(sync): sync drifted statuses with tracker` — status/priority/lead corrections
2. `docs: add missing projects to roadmap` — new rows, new project files
3. `chore: remove stale/absorbed roadmap entries` — cleanup
4. `docs: update initiative cross-references` — linkage fixes

---

## Tracker CLI Reference

### Linear

```bash
# All active projects
linear project list --all-teams

# Filter by status
linear project list --all-teams --status started

# All initiatives
linear initiative list

# Project details + issues
linear project get PROJECT_ID
linear project issues PROJECT_ID

# Status updates
linear project-update list PROJECT_ID
linear project-update create PROJECT_ID --health onTrack --body-file /tmp/update.md

# Create project
linear project create --name "Name" --team TEAM --status started \
  --lead "username" --start-date 2026-01-01 --target-date 2026-03-31

# Create issue
linear issue create --team TEAM --title "Title" \
  --description "Description" --project "Project Name" \
  --priority 2 --no-interactive

# Update project via GraphQL (fields not in CLI)
linear api 'mutation { projectUpdate(id: "ID", input: { priority: 2, statusId: "STATUS_ID" }) { success } }'

# Link project to initiative
linear api 'mutation { initiativeToProjectCreate(input: { initiativeId: "ID", projectId: "ID" }) { success } }'

# User list (resolve names to IDs)
linear user list
```

### beads

```bash
br list --status open          # All open items
br list --type epic            # All epics
br show ISSUE_ID               # Issue details
br update ISSUE_ID --status done
br dep add EPIC_ID ISSUE_ID    # Link issue to epic
```

---

## Status Emoji Reference

| Emoji | Meaning | Tracker Status |
|-------|---------|----------------|
| ✅ | Completed | Completed |
| 🚧 | In Progress | In Progress / Started / Maintenance |
| 🗓 | Planned / Ready | Backlog / Shaping / Discovery / Ready |
| ⏸ | Paused | Paused |
| ⛔ | Blocked | (annotation — project has named blocker dependency) |

## Key Rules

- **Never auto-resolve conflicts** — always ask the user
- Never remove items from roadmap without user approval
- Preserve existing table formatting and column alignment
- When adding new items, place them in the correct Category row
- Quarter assignments come from project Timeline fields
- If a project spans quarters, mark all relevant quarter columns
- Data refreshes are tracked in `data-refreshes/`, not on the main roadmap grid
- **Maintenance/catch-all projects (Tech Debt, Entitlements, UI/UX Improvements) do NOT belong on the roadmap grid.** If a maintenance project accumulates enough themed issues, break those out as a dedicated project instead
- When merging/absorbing rows, verify the sub-item exists as an issue in the parent tracker project before removing the row
- **Completeness check:** Before finalizing, verify every section has been populated. An empty array is acceptable (no findings), but never skip a category entirely
- **Blocked vs Paused:** Blocked projects have a named dependency preventing progress (red dashed Gantt bar + `⛔ Blocker Name` label, `badge-blocked`). Paused projects are simply deprioritized (purple dashed Gantt bar, `badge-paused`). Use `blocked` when a project names a blocker; use `paused` when just deprioritized

## Tracker Project Backing Requirement

**Every epic on the roadmap MUST have a corresponding tracker project.** Individual issues are not sufficient — epics represent project-level work.

### When adding epics to the roadmap

1. **Check tracker first** — search for a matching project
2. **If a project exists:** Proceed — add the epic with its tracker URL
3. **If no project exists:**
   - Do NOT add the epic as a roadmap-only placeholder
   - If the user explicitly requests adding it, **create the tracker project first**, then add the epic with the new URL
4. **Issue-level items** (bugs, small tasks) should NOT be elevated to roadmap epics. They belong as issues inside their parent project.

### During sync/review

Flag epics that lack tracker project backing:
- Report them in a **"Missing Tracker Project"** section
- For each, recommend: remove from roadmap, merge into existing project, or create a new project
- Do NOT silently keep unlinked epics — they drift and become stale
