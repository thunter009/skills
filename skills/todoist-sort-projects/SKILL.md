---
name: todoist-sort-projects
description: Alphabetize Todoist projects within each parent.
when-to-use:
- sort projects, alphabetize todoist, reorder sidebar
- When the project tree needs cleanup
category: pm
related-skills:
- todoist
---

# Todoist Sort Projects

Sorts every Todoist project alphabetically (case-insensitive) within its parent. Applies recursively to all sub-projects.

## Prerequisites

- `td` CLI installed and authenticated (`td auth login` — see `todoist` skill)
- Token is resolved automatically: `TODOIST_API_TOKEN` env var, else `td auth token view`, else the legacy `api_token` field in `~/.config/todoist-cli/config.json`

## Why it's needed

Todoist has no native "always sort" setting. Projects hold an explicit `child_order` field; new projects append to the end. This script reassigns `child_order` based on alphabetical name order.

## Usage

```bash
python3 ~/.claude/skills/todoist-sort-projects/scripts/sort.py
```

Or, if running from the agent-skills repo:

```bash
python3 skills/todoist-sort-projects/scripts/sort.py
```

Prints the number of projects reordered and any API errors.

## When to run

- After creating/renaming/reparenting projects
- On a recurring basis (weekly) to keep the sidebar tidy as new projects land

## Notes

- Inbox is always pinned at position 0 (not alphabetized)
- Numeric prefixes sort correctly (10_... before 20_...) because ASCII sort aligns with intent for Johnny Decimal naming
- `.` sorts before `_` in ASCII — `11.06_x` sorts before `11_planning`. If that's wrong, reparent the project rather than relying on sort order.
- The script makes a single `project_reorder` sync API call, so it's atomic
