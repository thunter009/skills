---
name: update-task-documentation
description: Sync task docs, roadmap, and README with real project state.
when-to-use:
- update task docs, sync tasks, refresh start-here
- When docs/tasks drift from code
user_invocable: true
category: pm
---

# Update task documentation with current state

## Goal

Synchronize docs/tasks/* with the actual current state. Confirm completion status, move files appropriately, and ensure Start Here and README reflect reality.

## Scope

- docs/tasks/{active,backlog,completed}/*.md
- docs/start-here.md (Roadmap + status)
- README.md (Current Status)

## Steps

0) Pre-flight Check
   - Read docs/start-here.md and check for "Your Roadmap" section (search for `### 2. Your Roadmap` or similar heading)
   - If missing, auto-generate from docs/tasks/active/*.md:
     - Parse active task files for titles
     - Create numbered list: first task gets emoji marker, rest unmarked
     - Link format: `[Task Title](tasks/active/filename.md)`
     - Insert before "## Documentation Structure" section
   - Continue to audit step

1) Audit
   - For each task in active/: confirm status via code/docs.
   - Move completed items to completed/ with completion date.
   - Ensure backlog items exist for upcoming work we've discussed.

2) Normalize
   - Ensure each task file has Summary, Action Items (checkboxes), Technical Details.
   - Add brief "Status" section at top (Planned, In Progress, Blocked, Complete).

3) Cross-Doc Sync
   - Update docs/start-here.md Roadmap statuses and links.
   - Update README.md "Current Status" if needed.

4) Output (pause)
   - Provide a concise report:
     - What moved (active -> completed), what added to backlog
     - Any status changes and link updates
   - Pause for confirmation before committing changes.

## Afterward

- Remind the user where we left off and the next intended action, then pause.
