---
name: park
description: Create a Todoist resumption task so paused work can restart cleanly.
when-to-use:
- park this, save for later, create resumption task
- When stopping mid-task
user_invocable: true
category: pm
---

# /park — Park Work for Future Session

Create a Todoist task that captures what to resume and how, with a prompt a future Claude session can use to pull context.

## Workflow

### 1. Gather Context

Determine from the conversation:
- **What was being worked on** (1-line summary for task title)
- **What's left to do** (concrete next steps)
- **Where context lives** (journal entries, beads, files, PRDs)
- **Which Todoist project** this belongs in

Also auto-detect:

```bash
# Git state — a future session needs to know this
echo "Branch: $(git branch --show-current)"
echo "Dirty files: $(git status --short | wc -l)"
echo "Unpushed commits: $(git log --oneline @{u}..HEAD 2>/dev/null | wc -l)"

# In-progress beads
br list --status=in_progress 2>/dev/null

# Check for .session-journal.md entries
test -f .session-journal.md && echo "Session journal exists" || echo "No session journal"
```

Also scan conversation for uncommitted follow-ups that should be bundled in. Before
creating any NEW tracker item for parked work, run the **followup-dedup** skill (entity
keywords → `search-dups.sh` → surface candidates); update an existing item over creating
a parallel one, and route per followup-dedup's Tracker-routing rules (canonical).

If unclear on any context, ask the user.

### 2. Build Resumption Prompt

Write a prompt that gives a fresh Claude session everything it needs:

```
Check agent journal at [path] for context. Then:
1. [concrete step]
2. [concrete step]
...
Related beads: [IDs]
Git state: branch X, N dirty files, M unpushed commits
```

Include:
- Agent journal path (if `/done` was run)
- `.session-journal.md` path (if entries exist)
- Bead IDs for in-progress work
- Git state (branch, dirty files, unpushed count)
- File paths for relevant configs/scripts
- Specific commands to run

Do NOT include:
- Full conversation replay
- Vague instructions ("continue working on X")
- Context the journal already captures

### 3. Create Todoist Task

For long descriptions, write to a temp file first to avoid shell escaping issues:

```bash
# Write description to temp file
cat > /tmp/park-desc.txt << 'PARK_EOF'
<resumption prompt with concrete steps>
PARK_EOF

# Create task WITH its description in one call — NOTE: td task add (NOT td task
# create). --stdin pipes the long/multi-line body without shell-quoting hell, and
# satisfies the write-guard (which requires a description + a real project at
# create time).
td task add "<short title>" \
  --project "<project>" \
  --priority p2 \
  --due "tomorrow" \
  --stdin < /tmp/park-desc.txt
```

**Title**: short, actionable (e.g., "Install Tailscale on NAS + fix SMB conflict")
**Due**: tomorrow by default, or ask user
**Priority**: p2 by default (p1/p2/p3/p4 strings, not numeric)

**Note:** `#ProjectName` in `td add` fails silently for multi-word project names. Always use `--project "Name"` flag or `td task move` after creation.

### 4. Confirm

Show the user the created task title + description. Done.

## Example

**Title:** `Finish E-014 V2: OpenClaw calendar read skill`

**Description:**
```
Check journal at ~/obsidian/agent-journal/sessions/clawd-bot-setup/2026-03/claude-code-2026-03-22-abc1.md

Resume bead bd-2we.2 (in_progress). PRD at docs/shaping/E014-calendar/slices.md.
gogcli is installed and authenticated. Next:
1. Create OpenClaw skill wrapper at ~/.openclaw/skills/calendar-read/
2. Wire gogcli commands into skill (list events, get event, free/busy)
3. Run exit condition from bead
4. br close bd-2we.2
```
