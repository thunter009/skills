---
name: enrich-ticket-detail
description: Flesh out thin or empty beads/Todoist items by mining git history, code-at-HEAD, closed tickets, and the session journal, then verify every drafted claim against live state before a gated write-back. Use when a task board is full of one-line stubs that can't be triaged cold.
when-to-use:
- flesh out / enrich / backfill thin task descriptions from project history
- A board (atrium cards, beads, Todoist) is full of stubs with no actionable detail
- Existing tickets reference work whose context lives in git/journal, not the ticket
- Before a planning or swarm pass that needs cold-start-complete tickets
category: pm
related-skills:
- colgrep
- polish-beads
- todoist-capture
---

# Enrich Ticket Detail (context → verified description)

Take tracker items that are **already on the board** but too thin to act on — a title and a one-liner like "Watch this" or "Incorporate into my workflow" — and turn each into a cold-start-complete description by **mining the project's own history**, then **verifying** the result against live state before writing anything back.

This is the enrichment counterpart to the atrium card sync: the sync faithfully copies whatever the tracker holds, so a thin ticket makes a thin card. This skill fixes the *source*, so the next sync carries real detail.

**It composes, it does not duplicate:**
- `/todoist-capture` — creates *new* cold-start-complete tasks from provided context. This skill enriches *existing* thin ones from mined context.
- `/polish-beads` — critiques ticket *quality* across dimensions. Run it *after* this skill fills in the substance.
- The atrium tracker sync (in dotfiles) — consumes the enriched descriptions onto cards. Run this, then re-run the sync.

**Hard rule — write nothing unverified, write nothing unapproved.** Every claim in a drafted description must be checked against the live repo/state, and every write goes through the dry-run gate in `scripts/apply-description.sh`. A plausible-but-wrong description is worse than a stub.

---

## Pipeline

```
select thin items → gather historical/project context → draft structured detail
→ VERIFY each claim against live state → gated apply (diff → approve → write)
→ (re-run the card sync)
```

### 1. Select the thin items (read-only)

```bash
# Open beads (cwd .beads/) + the matched Todoist project, with desc ≤ THRESHOLD chars.
THRESHOLD=80 scripts/select-thin-tickets.sh
```

Emits NDJSON: `{source(bd|td), id, title, desc_len, priority, current_description}`. Tune `THRESHOLD`; set `TD_PROJECT=<id|name>` to override the repo→project match, or `TD_SKIP=1`/`BD_SKIP=1` to scope to one tracker. Work the list highest-priority first.

### 2. Gather historical / project context (per item)

For each thin item, pull the context the ticket *should* have carried. Use the title + any keyword in it as the query:

```bash
kw="<key noun from the title>"
git log --oneline --all -S"$kw" | head -20         # commits that touched the concept
git log --oneline --all --grep "$kw" | head -20    # commits that mention it
git log --oneline -- "**/*$kw*"                     # history of matching paths
colgrep "$kw" .                                     # semantic code search (preferred over grep)
grep -rin "$kw" --include='*.md' docs/ README* 2>/dev/null | head   # docs / PRDs
```

Cross-reference other trackers and memory:
- **Closed/related tickets**: `br list --json | jq '.issues[] | select(.status=="closed")'` filtered by keyword; `td find-completed-tasks` for Todoist. Often the design lives in a sibling ticket.
- **Session journal / vault**: `grep -rin "$kw" ~/obsidian/agent-journal/sessions/` — past decisions and rationale.
- **Past sessions**: `cass` search if the work was done in a prior agent session.

Capture only facts you can cite (a commit SHA, a file path, a closed ticket id, a journal line). If a thin item yields *no* grounded context, leave it thin and note why — do not invent.

### 3. Draft a structured description

Mirror the cold-start-complete shape (the format the good cards already use):

```
## Goal        — one sentence, what "done" means
## Why         — the motivation / what breaks without it (cite the trigger)
## Current state — what exists today, with file paths / SHAs / ticket ids
## Next action — the first concrete command or step
## Acceptance  — how you'll know it's done
## References  — commits, files, tickets, journal lines you cited
```

Beads can also take `--design` / `--acceptance-criteria` as native fields, but put the full narrative in the **description** (that is the field the card sync reads).

### 4. Verify every claim (the distinctive step)

Before writing, adversarially check the draft against live state. Treat each factual claim as a hypothesis to refute:

- **Files exist at HEAD?** `test -f <path>` for every path you cited. Drop or fix dead paths.
- **Commits/PRs real?** `git cat-file -e <sha>^{commit}`; `gh pr view <n>` for any PR referenced.
- **Premise still true?** Re-read the code/state you describe — beads written weeks ago routinely carry stale assumptions. If the "current state" you drafted contradicts HEAD, fix it to reality.
- **Line/symbol references resolve?** `colgrep`/`grep` the symbol; don't cite a function that was renamed.
- **No fabricated specifics.** A number, table, or filename you can't trace to a source comes out.

Anything you cannot verify is **deleted** from the draft, or kept only with an explicit `⚠ unverified:` prefix so the human can judge. Prefer a shorter, fully-grounded description over a long speculative one.

### 5. Gated apply (diff → approve → write)

`scripts/apply-description.sh` is dry-run by default — it prints a unified diff and writes nothing until you pass `--yes`.

```bash
# preview (writes nothing):
printf '%s' "$DRAFT" | scripts/apply-description.sh td <id> -
printf '%s' "$DRAFT" | scripts/apply-description.sh bd <id> -

# after you (and ideally the user) have reviewed the diff:
printf '%s' "$DRAFT" | scripts/apply-description.sh td <id> - --yes
```

Surface the batch of diffs to the user and get a go before applying with `--yes` (per the gated-apply contract). It is idempotent: re-running with an unchanged draft is a no-op. After **beads** writes: `br sync --flush-only && git add .beads && git commit`.

### 6. Propagate to the board

Re-run the atrium tracker sync so the enriched descriptions land on the cards (the sync's marker-keyed upsert updates the existing cards in place — no duplicates).

---

## Scope & footguns

- **One-way enrichment of the source.** This writes to beads/Todoist; the card sync is a separate step. Don't write enriched text straight onto atrium cards — fix the tracker, let the sync carry it.
- **Real trackers — never auto-write.** The dry-run gate exists because this mutates the user's live beads and Todoist. Show diffs, get approval, then `--yes`.
- **Verification is not optional.** The value of this skill over a plain LLM rewrite is that nothing ungrounded survives. If you skip step 4 you've just added confident noise.
- **Thin-by-nature items stay thin.** Some tickets are genuinely a one-line reminder with no recoverable context. Leaving them is correct; don't pad them to hit a length target.
- **Todoist priority is inverse** (`4=urgent … 1=normal`) — don't reason about urgency from the raw int without mapping.

## References

- `scripts/select-thin-tickets.sh` — selection (read-only, NDJSON)
- `scripts/apply-description.sh` — gated write-back (dry-run unless `--yes`)
