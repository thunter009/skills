---
name: todoist-linkdump-eval
description: Evaluate raw-URL bookmark tasks in Todoist — fetch each link, post a verdict comment (KEEP-EVAL / SKIP / INSTALL-CANDIDATE), close the SKIPs. Designed to run recurring so link-dumps never accumulate.
when-to-use:
- "evaluate my link dumps"
- "triage bookmark tasks"
- Recurring /loop or cron sweep of bookmark-style tasks
- After todoist-project-triage flags a cluster of raw-URL tasks
category: pm
related-skills:
- todoist
---

# Todoist Link-Dump Evaluation

Raw URLs captured as Todoist tasks (X posts, GitHub repos, articles) are the single biggest backlog generator — they're p1 by capture default but represent zero committed work. This skill turns each into a verdict in one pass, on a cadence, so they never pile up again.

## Prerequisites

- `td` CLI authenticated (see `todoist` skill)
- Tavily extract script: `~/.claude/skills/extract/scripts/extract.sh '{"urls":["..."]}'` (batch up to 20 URLs/call)
- For X/Twitter links: xbird MCP tools (`get_tweet`, `get_thread`) if available; else extract.sh; mark unscrapable links honestly

## Workflow

1. **Find candidates.** A link-dump task = title or description is dominated by a bare URL, with no acceptance criteria. Default hunting grounds: the projects where the user captures (e.g. agent-skills, technology, bookmarks/read-later). Filter:
   ```bash
   td task list --project "id:<PROJECT_ID>" --json | jq -r '.results[] | select(.content+(.description//"") | test("https?://")) | .id'
   ```
   Exclude tasks that already have a verdict comment (idempotency). Comments are NOT shown by `td task view` — read them with `td comment list <id>`. Match both this skill's `verdict: <TOKEN>` format and any legacy `<TOKEN>: ...` comments from ad-hoc runs, so previously-evaluated bookmarks aren't re-processed:
   ```bash
   td comment list "$id" 2>/dev/null | grep -qE "verdict:|(KEEP-EVAL|SKIP|INSTALL-CANDIDATE):" && continue
   ```

2. **Fetch in batches.** Group URLs, extract up to 20 per call. X links via xbird when available.

3. **One verdict comment per task** — 2-sentence summary plus exactly one verdict:
   - `verdict: INSTALL-CANDIDATE` — a skill/tool worth installing; say what gap it fills
   - `verdict: KEEP-EVAL` — worth a deeper look; say why and what the eval would decide
   - `verdict: SKIP` — low signal, superseded, vaporware, or unscrapable-with-vague-title; say why
   Be skeptical: most bookmarks deserve SKIP.

4. **Close the SKIPs** — `td task complete <id>` (the command is `complete`, not `close`), never `td task delete`. Comment first: `td comment add <id> --content "triaged <date>: SKIP verdict (see eval comment)"`. Leave KEEP-EVAL and INSTALL-CANDIDATE open — those are now real, scoped tasks. (Or batch via `td-batch.sh comment` then `td-batch.sh close`.)

5. **Report.** Table of id → verdict, counts per verdict, and the top 1-3 INSTALL-CANDIDATEs with a one-line pitch each. Do NOT auto-install anything — installs are a supply-chain decision the user makes.

## Recurring use

Pair with /loop or a weekly cron: each run sweeps only tasks without a verdict comment, so it's cheap when the queue is empty. Suggested cadence: weekly.

## Anti-patterns

- Auto-installing INSTALL-CANDIDATEs (supply-chain decision — user only)
- Deleting instead of closing
- Verdicting from the URL slug without fetching the content
- Re-evaluating tasks that already carry a verdict comment
