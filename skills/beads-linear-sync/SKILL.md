---
name: beads-linear-sync
description: Sync beads and Linear so agent state and human tracker stay aligned.
when-to-use:
- sync beads with linear, pull from linear, push to linear
- When beads and Linear drift
allowed-tools:
- Bash
- Read
- Write
- Edit
- Glob
- Grep
- AskUserQuestion
permissions:
- read
- bash
- write
category: pm
---

# /beads-linear-sync

Bidirectional sync between `br` (beads_rust) and `linear` CLI. Beads is the agent workspace; Linear is the human UI.

## Architecture

```
Linear (human UI)  <──pull──>  beads (agent workspace)
                   <──push──>
```

- **Pull**: Import Linear issues into beads so agents can work locally
- **Push**: Update Linear to reflect beads state changes (status, priority, new issues)
- **Reconcile**: Detect drift, report conflicts, resolve with configurable policy

## Prerequisites

```bash
br --version    # beads_rust CLI
linear --version  # Linear CLI (schpet/linear-cli)
```

Both must be authenticated. Beads must be initialized (`br init` if no `.beads/` dir).

## Arguments

| Flag | Default | Description |
|------|---------|-------------|
| `--mode` | `pull` | `pull`, `push`, `reconcile`, or `dry-run` |
| `--project` | none | Linear project filter |
| `--team` | none | Linear team key filter |
| `--cycle` | none | Linear cycle filter (e.g., `active`) |
| `--conflict` | `newest` | Conflict policy: `newest`, `prefer-local`, `prefer-linear` |
| `--label` | none | Apply a Linear label to agent-created issues (e.g., `agent-managed`) |

## State Mapping

| Linear State | Beads Status | Direction | Notes |
|---|---|---|---|
| `triage` | `open` | pull only | push: `open` -> `unstarted` (lossy; triage/backlog collapse) |
| `backlog` | `open` | pull only | push: `open` -> `unstarted` (lossy; triage/backlog collapse) |
| `unstarted` | `open` | both | |
| `started` | `in_progress` | both | |
| `completed` | `closed` | both | |
| `canceled` | `closed` | pull only | push: `closed` -> `completed` (lossy; canceled state lost) |

**Lossy mappings**: Beads has 3 statuses vs Linear's 6 states. Pulling is lossless, but pushing `open` always becomes `unstarted` and `closed` always becomes `completed`. If the original Linear state was `triage`, `backlog`, or `canceled`, that nuance is lost on push. To preserve it, store the original Linear state in the `--external-ref` or description marker.

| Linear Priority | Beads Priority | Notes |
|---|---|---|
| 0 (No priority) | P4 | backlog |
| 1 (Urgent) | P0 | critical |
| 2 (High) | P1 | high |
| 3 (Medium) | P2 | medium |
| 4 (Low) | P3 | low |

## Workflow

### 1. Detect Context

```bash
# Verify tools available
br --version 2>/dev/null || { echo "br not found"; exit 1; }
linear --version 2>/dev/null || { echo "linear not found"; exit 1; }

# Check beads initialized
br info 2>/dev/null || { echo "No .beads/ dir; run br init first"; exit 1; }

# Get Linear team context
linear team list --no-pager 2>/dev/null | head -5
```

### 2. Pull (Linear -> Beads)

Import Linear issues into beads. Safe by default; never overwrites local beads changes without confirmation.

```bash
# 1. Fetch Linear issues (scoped). linear list has no --json; parse text output
#    Or fetch each issue individually with --json for structured data
linear issue list --all-states --all-assignees --limit 100 --no-pager
# For structured data, iterate identifiers through:
linear issue view ENG-123 --json --no-pager

# 2. For each Linear issue, check if bead exists
#    Match by: Linear URL in bead description, or title match
br search "ENG-123" 2>/dev/null

# 3. Create missing beads (use --external-ref for the Linear link)
br create --title "Issue title" --priority 2 --status open \
  --external-ref "linear:ENG-123" \
  --description "Linear: ENG-123 - https://linear.app/team/issue/ENG-123"

# 4. Update existing beads if Linear state is newer
br update <bead-id> --status in_progress --priority 1
```

**Matching strategy** (in priority order):
1. External ref match: `br list --json | jq '.[] | select(.external_ref == "linear:ENG-123")'`
2. Description contains Linear identifier: `br list --desc-contains "ENG-123"`
3. Title search: `br search "issue title keywords"`

Note: `br search` is free-text (title-oriented). `--external-ref` is not directly queryable; use `br list --json` + filter for structured matching.

### 3. Push (Beads -> Linear)

Update Linear to reflect beads state. Only pushes changes since last sync.

```bash
# 1. List beads with recent changes
br list --status open --json 2>/dev/null
br list --status closed --json 2>/dev/null
br list --status in_progress --json 2>/dev/null

# 2. For each bead with a Linear link, check if states match
linear issue view ENG-123 --json --no-pager

# 3. Update Linear if bead state is newer
linear issue update ENG-123 --state started
linear issue update ENG-123 --priority 2

# 4. Create Linear issues for beads without a Linear link
linear issue create --title "Bead title" --description "$(cat /tmp/bead-desc.md)" \
  --priority 2 --state unstarted --no-interactive --no-use-default-template

# 5. Write Linear link back to bead (append to existing description, don't clobber)
#    Read current desc first, append Linear ref
br update <bead-id> --external-ref "linear:ENG-456"
```

### 4. Reconcile (Bidirectional)

Full bidirectional sync with conflict detection.

```bash
# 1. Pull Linear state
# 2. Pull Beads state
# 3. Compare matched pairs, detect conflicts where both changed
# 4. Apply conflict policy (newest/prefer-local/prefer-linear)
# 5. Push resolved state to both sides
# 6. Report: created, updated, conflicted, skipped
```

**Conflict detection**: Compare `updatedAt` timestamps. If both sides changed since last sync, apply conflict policy.

### 5. Dry Run

Same as reconcile but no mutations. Outputs a diff report:

```
## Sync Preview

| Action | Source | ID | Title | Change |
|--------|--------|----|-------|--------|
| create-bead | Linear | ENG-456 | New feature | Not in beads |
| update-linear | Beads | bd.a3f | Fix bug | open -> closed |
| conflict | Both | ENG-123/bd.7c2 | Auth refactor | Linear: started, Beads: closed |
| skip | n/a | bd.9e1 | Local-only task | No Linear link |
```

## Sync Metadata

Two mechanisms for linking beads to Linear issues:

**1. External ref** (preferred; structured, queryable):
```bash
br create --external-ref "linear:ENG-123" ...
# or after the fact:
br update <bead-id> --external-ref "linear:ENG-123"
```

**2. Description marker** (fallback; human-readable, stores URL and sync timestamp):
```
Linear: ENG-123 - https://linear.app/team/issue/ENG-123
Linear-state: started  # original Linear state (preserves lossy mappings)
Linear-synced: 2026-03-26T14:30:00Z
```

Use both: `--external-ref` for matching, description marker for audit trail and original state preservation.

## Common Patterns

### Pre-Work Session Pull

```
/beads-linear-sync --mode pull --project "Current Sprint"
```

Ensures agent has latest Linear state before starting work.

### Post-Work Session Push

```
/beads-linear-sync --mode push
```

Updates Linear with all beads changes from the session.

### Weekly Reconciliation

```
/beads-linear-sync --mode reconcile --conflict newest
```

Full bidirectional sync, newest-wins for conflicts.

### Agent-Only Issues

Use `--label agent-managed` to tag issues created by agents in Linear, so humans can filter them:

```
/beads-linear-sync --mode push --label agent-managed
```

## Gotchas

- **Linear CLI state values**: `triage`/`backlog`/`unstarted`/`started`/`completed`/`canceled` (NOT "In Progress")
- **Linear priority is inverted**: 1=Urgent (maps to P0), 4=Low (maps to P3), 0=None (maps to P4)
- **br sync vs this skill**: `br sync` only syncs SQLite<->JSONL. This skill syncs beads<->Linear
- **No `--mine` flag**: `linear issue list` defaults to your issues. Use `-A` for all assignees
- **Linear CLI needs `--no-interactive --no-use-default-template`** for scripted creates
- **Linear `--json` output**: `identifier` field is human-readable (ENG-123), NOT the UUID. Use `id` field for GraphQL mutations
- **Rate limiting**: Add 100ms delay between Linear API calls in bulk operations
- **Beads prefix**: Check `br config get issue_prefix`; may be `bd` or custom. Don't hardcode
- **Linear team context required**: `linear issue list` fails without team context. Either use `--team KEY`, run from a dir matching the team key, or configure `.linear.toml`
- **Description clobbering**: `br update --description "..."` replaces the entire description. Read existing description first and append the Linear marker, or use `--external-ref` for the link

## Post-Sync Housekeeping

After any sync that modifies beads, flush and commit:

```bash
br sync --flush-only          # export DB to JSONL
git add .beads/ && git commit -m "sync beads with linear"
```

Required per project conventions; `br` never runs git itself.

## Error Recovery

If sync fails mid-operation:
1. Re-run with `--mode dry-run` to see current state
2. Fix conflicts manually if needed, then re-run sync
3. Use `br sync --status` to verify beads DB/JSONL consistency

## Integration with Other Skills

- **/groom**: Run pull before grooming to ensure beads reflect latest Linear state
- **/ship**: Run push after shipping to update Linear with completed work
- **/sweep-epics**: Run after push to close Linear parent issues with all children done
- **/meeting-sync**: Meeting action items flow to Linear, then pull brings them to beads
