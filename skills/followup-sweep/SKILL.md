---
name: followup-sweep
description: Weekly cross-tracker follow-up hygiene sweep — consume the auto-flagged vault punch list, dedup Todoist work-stream Inbox sections, and merge duplicate tracker items. Scheduled companion to followup-dedup.
when-to-use:
- Weekly scheduled run (Claude Code cron) or "run the follow-up sweep"
- Todoist inbox sections have accumulated possible duplicates
- The vault punch list `_untracked-followups.md` has unprocessed blocks
- After a burst of multi-agent sessions that may have leaked or double-filed follow-ups
category: pm
related-skills:
- followup-dedup
- todoist
- done
---

# Follow-up Sweep

Periodic hygiene pass over follow-up trackers. Per-session dedup (followup-dedup inside /done and /clean) catches duplicates at write time; this sweep catches what slips through — sessions that ended without /done, non-Claude agents (codex/cursor share the deployed skills but not CLAUDE.md rule 7), and cross-session paraphrase drift.

Two inputs, one protocol:

## Step 1: Consume the vault punch list

`$AGENT_VAULT_PATH/sessions/_untracked-followups.md` (default vault `~/obsidian/agent-journal`) accumulates blocks auto-flagged by `done/scripts/auto-journal-worker.sh` — journal lines that looked like follow-ups but carried no `(tracking:)` tag.

For each block (one per `## <date> — <project> (session <id>)` heading):

1. Judge whether each line is a real follow-up or noise (the flagger's regex is deliberately loose — narrative mentions of "follow-up" land here too). Dismiss noise silently.
2. For real items, run the **followup-dedup** protocol: entity keywords → `bash ~/.claude/skills/followup-dedup/scripts/search-dups.sh "<kw1>" "<kw2>" ...` → surface candidates → update existing or create per followup-dedup's **Tracker-routing rules** (canonical — includes Todoist Inbox-section placement + cold-start standard).
3. Delete the processed block from the punch list (processed = filed, updated, or dismissed). The file should be empty of blocks after a clean sweep.

## Step 2: Dedup Todoist Inbox sections

For each work-stream project with an "Inbox" section (list via `td`, see the todoist skill):

1. List that section's open tasks.
2. For each task, extract entity keywords (people, artifacts, IDs, action verb — not the full title) and run `search-dups.sh`.
3. `match_count ≥ 2` + same verb = duplicate cluster → **merge**: keep the item with the most cold-start context (or the older one on a tie), fold the other's unique context into it (links, deadlines, decisions — skip tangential info), then close/delete the duplicate. Cross-tracker duplicates (bead + Todoist twin for the same work): keep the tracker that matches the routing table, close the other with a pointer comment.
4. While there, upgrade surviving items that fail the cold-start standard (goal, why, paths/IDs/URLs, current state, next action) using context from the duplicate or the session journal.

## Step 3: Report

End with a table — no silent work:

| Section | Result |
|---|---|
| Punch list | N blocks: filed X, updated Y, dismissed Z |
| Todoist inbox dups | merged N clusters (list IDs) |
| Cold-start upgrades | N items |

## Guardrails

- **Headless/cron runs are conservative**: apply same-tracker merges only when `match_count ≥ 2` AND same verb AND same project/work-stream; anything weaker — and ALL cross-tracker merges — goes in the report as a proposal, not an action. Interactive runs may confirm the proposals (in atrium, batch verdicts via the decision-canvas skill).
- Never bulk-delete: every close/delete names the surviving item's ID in a comment first.
- This sweep files and merges; it does NOT start work. New scope discovered mid-sweep becomes a tracker item per the routing table, nothing more.
- Respect per-session dedup: if /done just ran in an active session (punch list block from today), leave that block for the session's own /done unless it's clearly finished.
