---
name: groom-backlog
description: Groom docs/tasks and start-here with consistent global ticket IDs.
when-to-use:
- groom backlog, sync start-here, fix task ids
- When task docs are drifting
user_invocable: true
category: pm
---

# Backlog Grooming & Start-Here Sync

## Goal

- Audit and groom all tickets across docs/tasks/{active,backlog,completed} and docs/start-here.md.
- Ensure roadmap phases are accurate; add/adjust phases where relevant.
- Enforce globally unique sequential ticket IDs across active, backlog, and completed tickets.
- Verify and update all links in docs/start-here.md (and root README.md if referenced) to be current and valid.

## Scope

- Files:
- docs/start-here.md
- docs/tasks/active/*.md
- docs/tasks/backlog/*.md
- docs/tasks/completed/*.md
- docs/tasks/README.md
- README.md (root)
- Optional references:
- docs/reference/*, docs/how-to-guides/* for link validation

## Global Ticket ID Policy

- Single global numeric sequence across all tickets (active, backlog, completed).
- Filenames:
- docs/tasks/backlog/NNN-slug.md
- docs/tasks/active/NNN-slug.md
- docs/tasks/completed/NNN-slug.md
- Titles: "[#NNN] Title"
- Keep the same NNN when moving tickets between folders (no renumbering).
- References across docs use #NNN.
- If legacy prefixes exist (e.g., 01-, B-001), migrate to global NNN and update references.

## Steps

1) Inventory
   - List all tasks in active/, backlog/, completed/.
   - Extract any existing numeric IDs from filenames and titles across all three folders.
   - Build a global ID map: ID -> {path, title, status}.
   - Detect:
     - Missing IDs (no NNN in filename/title)
     - Duplicates (same NNN on multiple tickets)
     - Collisions (filename NNN != title NNN)

2) Normalize format
   - Ensure each task file has:
     - Summary (2-3 sentences)
     - Action Items (checkbox list)
     - Technical Details (code refs, deps)
   - If missing sections, add stubs and extract details from existing content.
   - Ensure title format is "[#NNN] ..." once IDs are assigned/fixed.

3) Phase alignment
   - Read docs/start-here.md "Your Roadmap" section.
   - Map each task to a defined phase. If no suitable phase exists, propose/insert a new phase with a concise title and add a matching dev-guides placeholder filename.
   - Update roadmap entries with statuses:
     - Completed (with completion date if known)
     - In progress
     - Planned
     - Do this next (one item max)

4) Link audit
   - Validate all links in docs/start-here.md (and any links it references) point to real files/paths in the repo.
   - Update broken or outdated links to current locations.
   - Ensure the Quick Start links and "Documentation Structure" links match the actual tree.

5) ID policy application and conflict resolution (Global Uniqueness)
   - Determine the next available global ID: max(existing IDs) + 1.
   - Assign IDs:
     - For any ticket (in backlog, active, or completed) missing an ID:
       - Assign the next available global ID and increment.
       - Rename file to NNN-slug.md and update the title to "[#NNN] ...".
     - For duplicates/collisions:
       - Keep the lowest NNN on the earliest-created or most authoritative ticket (use git history or context if available).
       - Reassign new IDs to others using the next available NNN, and note old -> new mappings.
   - Reference updates:
     - Update any references within docs/start-here.md, README.md, and other docs to the new NNN-slug filenames and "[#NNN] ..." titles.
     - Search-and-replace legacy IDs/prefixes (e.g., 01-, B-001) to the new #NNN scheme where appropriate.

6) Consistency pass
   - Ensure docs/tasks/README.md conventions match actual filenames and formats.
   - Document the global ID policy (NNN-slug.md, "[#NNN] Title", retain NNN across moves, use #NNN references).
   - If roadmap statuses changed, reflect them in README.md "Current Status".

7) Output a summary plan (pause)
   - Provide a delta summary:
     - New IDs assigned
     - Duplicates resolved (old -> new ID mappings)
     - Renames performed / proposed
     - New/updated phases
     - Link fixes
     - Tasks moved or status-changed
   - Pause for approval before making file changes if running in a constrained environment. Otherwise, proceed to apply changes and report diff-like summaries.

## Deliverables

- Updated docs/start-here.md with accurate roadmap, links, and phase mapping.
- Tickets normalized with globally unique IDs, consistent filenames, and standardized structure.
- Updated docs/tasks/README.md describing the global ID policy and examples.
- Short changelog of edits and file path changes.

---

### Optional snippet for docs/tasks/README.md

```markdown
## Global Ticket IDs

-  A single global numeric ID (NNN) is used across all tickets (backlog, active, completed).
-  Filenames: NNN-slug.md. Titles: "[#NNN] Title".
-  Keep the same NNN when moving a ticket between backlog/, active/, and completed/.
-  Reference tickets as #NNN across docs.

Examples
-  backlog/001-improve-logging.md -> "[#001] Improve Logging"
-  active/014-implement-auth.md -> "[#014] Implement Auth"
-  completed/009-setup-ci.md -> "[#009] Setup CI"
```
