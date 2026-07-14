---
name: todoist-capture
description: Convert loose context — a conversation, runbook, diagnosis, decision, error dump, or doc — into well-formed Todoist task(s) that are deduped, correctly placed, and cold-start-complete. The inverse of todoist-kickoff-prompt (which goes task → prompt).
when-to-use:
- make this a todoist task / capture this as a task / write it up as a todoist task with full detail
- A session surfaces follow-up work, a runbook, or a hand-off the user wants tracked
- A diagnosis / decision / error should become an actionable, self-contained task
- Turning a multi-step plan or runbook into a task the user (or a future agent) can execute cold
category: pm
related-skills:
- todoist
- todoist-inbox-triage
- todoist-kickoff-prompt
- todoist-project-triage
---

# Todoist Capture (context → task)

Turn whatever just happened — a diagnosis, a runbook, a decision, a pile of findings, a hand-off — into a Todoist task someone can pick up **cold** and act on, without re-reading the conversation. This is the inverse of `todoist-kickoff-prompt` (task → prompt).

The bar for a good captured task: it states **what to do, why, the current state, the exact next steps, how to verify, and where to look** — and it does **not** duplicate something already in Todoist.

## Prerequisites
- `td` CLI installed + authenticated (`td auth status`). See the `todoist` skill for setup.

## Workflow

### 1. Distill the context into task(s)
Extract the *actionable* core. **One task per discrete, independently-completable outcome** — split a multi-outcome blob; don't cram, don't shatter. For each candidate draft a:

- **Title** — imperative, specific, scannable, names the entity/system. "Set up Google Calendar OAuth for X", not "Calendar stuff".
- **Description** — the cold-start payload (Step 4).

Resist padding. If the context is one trivial line, it's a one-line task — no ceremony.

### 2. Dedup BEFORE writing (mandatory)
Search Todoist for existing tasks on the same topic/action. Match on **entity keywords + action verb**, not exact title — try 2–3 angles.

```bash
td task list --filter "search: <entity>" --json | \
  python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('results',d); [print(t['content'],'|',t['id']) for t in r]"
```

Then decide per candidate:
- **Near-match that already has cold-start detail** → make NO change. Report `already tracked: <id>`.
- **Match that's a bare placeholder or a broad epic** → ENRICH the existing task instead of creating a sibling (Step 5b).
- **No match** → create new (Step 5a).

Surface the dedup result + your plan (create / enrich / skip) to the user **before** writing.

### 3. Place it — don't dump in Inbox
- **Parent** — if it's a sub-step of a tracked epic/task, make it a subtask (`--parent id:<epic>`); it inherits the project. Keeps epics from bloating.
- **Project / Section** — match the topic (`--project "Name"`, `--section <ref>`).
- **Priority** — `p1` urgent … `p4` none; match the surrounding work's convention (check the parent/sibling tasks).
- **Due / labels** — only if the context implies them. **Don't invent deadlines.**

### 4. Write a cold-start-complete description
The description is the deliverable. Include, as relevant:

- **GOAL** — the outcome in one line.
- **WHY** — what it unblocks / why it matters.
- **CONTEXT** — where it came from (session, related IDs/beads), so it isn't a mystery in 3 weeks. **Convert relative dates to absolute.**
- **STEPS** — exact commands/clicks, in order, copy-pasteable. Mark which steps the **user must do** (interactive logins, secret entry, OAuth consent) vs. agent-doable.
- **VERIFY** — how to confirm it worked.
- **NEXT / AFTER** — follow-on wiring or the hand-back ("ping me to do X").
- **REFS** — file paths, bead/issue IDs, URLs, related epics.

Hard rules:
- **Never put secrets** (tokens, passwords, client secrets) in a task. Reference where they live; have the user handle them.
- For anything multi-line, pipe the body via `--stdin` to dodge shell-quoting hell.

### 5a. Create
```bash
td task add "Imperative, specific title" \
  --parent id:<epic-id> --priority p2 --stdin --json <<'EOF'
GOAL: ...
WHY: ...
CONTEXT (YYYY-MM): ...
STEPS:
  1. ...
VERIFY: ...
NEXT: ...
REFS: ...
EOF
```
(`--parent` inherits the project; otherwise add `--project`/`--section`.)

### 5b. Enrich an existing task
`td task update <id> --description` **replaces** the description — read the existing one first and merge, don't clobber. To *append* without losing history, prefer a comment:
```bash
td task view <id>                          # read current description first
td task comment add <id> --stdin <<'EOF'   # append, non-destructive
<new context>
EOF
```

### 6. Confirm
Report each created/updated task: title, id, URL, placement. If you split into several, skipped a dup, or enriched instead of created — say so explicitly.

## Anti-patterns
- Creating a task that duplicates an existing one — always run Step 2 first.
- A bare-title task when the context was rich — you threw away the cold-start value.
- Burying secrets in the description.
- Inventing due dates the user didn't ask for.
- One mega-task for what are 3 independent outcomes (or 5 tiny tasks for one).
- Dumping in Inbox when a parent epic / project obviously fits.

## Composability
- Often the tail end of a working session: "we found 3 follow-ups → capture them."
- Pairs with `todoist-kickoff-prompt` (the reverse): capture now, generate a kickoff prompt later when it's time to execute.
- After `todoist-inbox-triage` / `todoist-project-triage`, use this to (re)write under-specified tasks to the cold-start bar.
