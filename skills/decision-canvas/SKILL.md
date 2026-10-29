---
name: decision-canvas
description: |
  Present batched user decisions as an interactive atrium canvas with inline grounding — code snippets with real line numbers, click-to-open file links, and (for data questions) charts built from live prod data. Use when ATRIUM=1 AND a decision set exceeds what AskUserQuestion handles well:
  (1) More than 4 questions, or options that overflow 4-choice limits
  (2) Decisions the user can't judge without inspecting evidence (code, diffs, migrations, configs)
  (3) Data questions — "which threshold", "is this distribution acceptable", "which cohort" — where the user needs to SEE the data to decide
  (4) Audit/review/plan follow-ups with per-item verdicts (open questions, finding triage, bead grooming verdicts)
  Keep AskUserQuestion for quick forks: ≤4 questions, ≤4 options each, no evidence inspection needed. Outside atrium (no ATRIUM=1), always use AskUserQuestion.
when-to-use:
- "work through these open questions in a canvas"
- end of an audit/review/plan with 3+ decisions pending
- any decision where the honest answer is "look at the code/data first"
- triaging findings, grooming verdicts, threshold/cutoff choices
---

# Decision Canvas

Turn a batch of decisions into an atrium canvas the user fills in and sends back: one card per question, recommendation pre-selected, evidence embedded in-line so the user never has to leave the canvas (or trust your summary) to decide.

## The contract

Every canvas MUST have:

1. **One card per question** — title, 1-line description, short context `Text`, and a `Radio` bound to a unique state key. Pre-select your recommendation in `state` and mark it `(recommended)` in the label.
2. **A per-question notes `Textarea` on every card** — always, bound to `/{qid}_notes`, so the user can qualify *that one* decision inline ("yes but only for prod", "recommended is wrong because…") without dumping everything into the global box. The generator adds this automatically for each question; `{qid}_notes` joins the reply schema. Override the placeholder per question with `notes_placeholder`.
3. **Grounding per card** — a `Collapsible` ("Grounding — evidence", `defaultOpen: false`) holding the evidence: `Code` snippets (with `filePath` + `startLine` so gutters are honest), `atrium://commands/file.open` link buttons, muted `Text` for facts, and charts for data questions (see below).
4. **A global notes `Textarea`** — bound to `/notes`, for cross-cutting overrides that aren't tied to a single question.
5. **A submit `Button`** — `send_to_agent` with `{"payload": {"$state": ""}}`. Without it the user cannot reply. Set `--send-framing` at note-create time so the payload arrives labeled.
6. **A Resolution card — always, once the reply comes back.** The canvas is not complete until the session that receives the reply patches a `Resolution` card in (chosen answer + outcome per question). This is mandatory, not a nicety, and it holds **even when the canvas was passed back to a calling agent session** — whichever session parses the reply owns the resolution patch (see "After the reply"). A canvas with answers but no Resolution card is an unfinished decision record. The card goes **at the top**, directly under the heading and intro. On a `--tabs` canvas it fills the Resolution tab instead, and the tabs open on it. The heading gains a `✅`, and the submit button stops asking for a send. `--resolution --canvas` does all three.

State keys ARE the reply schema: name them `q1_<topic>`, `q2_<topic>`, … so the returned JSON parses on sight.

**Use `--tabs`.** A stack of cards with evidence blocks is a long scroll in a half-width pane. `--tabs` puts each question card in its own tab, plus a `Resolution` tab that waits for the reply. Global notes and the Send button stay below the tabs, so Send is always visible. A tab label defaults to the qid (`q3_ci_cache` → `3 ci cache`); set `tab` per question for a better one or two words. The Tabs element uses `defaultValue`, not a bound `value`: a bound tab position would land in the reply payload.

## Naming & provenance (so canvases are findable later)

Decision canvases accumulate; an ad-hoc title ("Audit: open questions") is unfindable in a month. Every canvas MUST be created with:

- **Title**: `Decisions: <topic> (<YYYY-MM-DD>)` — e.g. `Decisions: repo-audit open questions (2026-07-02)`. The `Decisions:` prefix makes the whole family one search away; the date disambiguates recurring topics (grooming, sprint reviews).
- **Folder**: `--folder decisions` — groups all decision canvases under one node in the notes tree instead of scattering them through the workspace root.
- **Tags**: `--tags decision,<topic-slug>,<tracker-ids>` — include the bead/PR/task IDs the decisions concern (e.g. `decision,repo-audit,bd-cor34`). Tags are searchable; tracker IDs make the canvas discoverable from the ticket side.
- **Provenance footer**: set `provenance` in the manifest (rendered as a muted footer line) with the calling pane (id + name), the session id, the driving artifact, and the date — e.g. `pane 29724c0c "Canvas subtab link" · session e93271… · source: repo-audit report · 2026-07-02`. `meta.json` records which pane authored the note, but panes die with sessions; the footer is the durable tie. Name the pane, not just the id — ids are unreadable in a room full of canvases.

## Where the canvas opens — a sub-tab of the calling pane

A canvas with no visible link to the session that asked for it is a puzzle. With several agents running, the user cannot tell which pane wants which answer. Open the canvas as a sub-tab of your own pane. The tab group is the link.

**Verified atrium 0.347.0, 2026-10-20.** `note open "$NOTE_ID" --split "$ATRIUM_PANE_ID" --direction subtab --json` loads the note into a new notepad grouped under the caller. `workspace.json` shows `subTabGroups.<caller>.order` = `[caller, notepad]` and the notepad's `currentNoteId` = the note. The canvas renders, and the tab label shows the note title. The 0.330.0 limits are gone: `note open` used to ignore target panes, and an empty notepad subtab could not load a note.

The sub-tab opens behind your chat, because the group's visible tab stays on the caller. Tell the user in chat that the canvas is in the sub-tab next to this chat. Do not pass `--focus`: it switches the user's active room and takes keyboard focus from whatever they type.

Fallback: when the split fails (no app UI, caller pane not in a room), run plain `note open "$NOTE_ID" --json`. It opens the canvas as a sibling in your room. When that fails too, the note is still durable on disk: give the user its id.

**Rename the notepad to the exact note title.** `pane list` reports an unrenamed notepad as `Notepad`. `atrium-workspace-sweep` keeps a session-less notepad out of its close list only when the pane name contains `Decisions` (`hold_empty_reason` in `skills/atrium-workspace-sweep/scripts/classify.py`). Use the title itself, never a variant. A renamed notepad can later copy its pane name into the note title and set `titleManual: true` (bd-k5tm). With the exact title, that copy changes nothing.

Do not put status or the caller in any pane name. The old `● Decisions ← <caller>` names replaced the topic and date in 72 note titles (all 72 carry `titleManual: true`, measured 2026-10-13). Status lives in the canvas: `--resolution` puts the Resolution card at the top and prefixes the heading with `✅`. `decision_index.py` reads status from the canvas, not from a name.

**Your own pane.** If it still carries a launcher default, rename it to a 10–20 char work description before you open the canvas. The provenance footer names it.

**Close the loop after acting — always**: once decisions come back and you've executed them, you MUST patch a `Resolution` card into the canvas (chosen answer per question + what you did: tracker IDs created/updated, commits, verification results). The canvas then reads as a complete decision record. This step is non-optional. It fires even when another session created the canvas: the session holding the reply patches the Resolution before its turn ends.

## Workflow

```bash
# 1. Build a manifest (see schema below) describing questions + grounding.
#    Snippets/queries are resolved AT BUILD TIME from real files/data — never paste code by hand.
# 2. Generate skeleton + patches:
python3 <skill-dir>/scripts/build_question_patches.py manifest.json --tabs \
  --skeleton-out /tmp/spec.json --patches-out /tmp/patches.jsonl

# 3. Name YOUR pane before the canvas opens — the provenance footer names it.
#    Substitute a real 10-20 char description for the placeholder; no script
#    can invent one for you.
CALLER=$("$ATRIUM_CLI_PATH" pane list --json | jq -r --arg me "$ATRIUM_PANE_ID" \
  '.[] | select(.id == $me) | .name')
case "$CALLER" in
  ""|claude-code|codex|gemini|cursor-agent)
    "$ATRIUM_CLI_PATH" pane rename "$ATRIUM_PANE_ID" --name "<10-20 char work desc>" ;;
esac

# 4. Create the note, then open it (separately — `note open --json` returns the
#    pane id, `note new --open` does not). Title/folder/tags per
#    "Naming & provenance" below — non-optional.
NOTE_TITLE="Decisions: <topic> ($(date +%F))"
NOTE_ID=$("$ATRIUM_CLI_PATH" note new --type canvas \
  --title "$NOTE_TITLE" \
  --folder decisions --tags "decision,<topic-slug>,<tracker-ids>" \
  --source agent \
  --send-framing "Decisions (canvas '{noteTitle}', note {noteId}):\n\n{payload}" \
  --spec /tmp/spec.json --json | jq -r '.meta.id // .id')
# Sub-tab of this pane; a sibling in this room when the split fails.
NOTE_PANE=$("$ATRIUM_CLI_PATH" note open "$NOTE_ID" --split "$ATRIUM_PANE_ID" \
  --direction subtab --json | jq -r '.paneId // empty')
[ -n "$NOTE_PANE" ] || NOTE_PANE=$("$ATRIUM_CLI_PATH" note open "$NOTE_ID" --json | jq -r '.paneId // empty')
# The exact title, never a variant (see "Where the canvas opens").
[ -n "$NOTE_PANE" ] && "$ATRIUM_CLI_PATH" pane rename "$NOTE_PANE" --name "$NOTE_TITLE"
"$ATRIUM_CLI_PATH" note canvas-patch "$NOTE_ID" < /tmp/patches.jsonl

# 5. End your turn, and say the canvas is in the sub-tab next to this chat. The
#    reply arrives as a framed user turn when they hit Send. Parse the state
#    JSON, act on each decision, confirm what you did.

# 6. ALWAYS close the loop: after acting, patch a Resolution card into the SAME note.
#    Write a resolution manifest {title?, summary?, date, items:[{qid, decision,
#    outcome}]} (see "After the reply"). Read the live canvas first: the script
#    needs it to put the card under the heading, mark the heading ✅, relabel the
#    submit button, and turn option values into the labels the user clicked.
"$ATRIUM_CLI_PATH" note read "$NOTE_ID" > /tmp/canvas.json
python3 <skill-dir>/scripts/build_question_patches.py resolution.json \
  --resolution --canvas /tmp/canvas.json --patches-out /tmp/resolution.jsonl
"$ATRIUM_CLI_PATH" note canvas-patch "$NOTE_ID" < /tmp/resolution.jsonl
# Read it back. The command is `note read`; there is no `note show`. Expect 1.
# 0 = the patch missed. 2+ = duplicate references: re-run --resolution against
# a fresh read (see "Amend a Resolution"). Other `resolution*` keys are addenda.
"$ATRIUM_CLI_PATH" note read "$NOTE_ID" \
  | jq '.elements[.root].children | map(select(. == "resolutionCard")) | length'
# No pane rename: the ✅ heading and the top card carry the status.
#    $NOTE_ID is the note the canvas already lives in. Cross-session, the reply's
#    framing carries {noteId} — read it from there (fallback: note list --folder).
```

### Adding questions to an open canvas

A new question can join a canvas the user is already filling in. Do not open a second canvas. Do not run the fresh build again: its counter keys restart at `txt_1`, and its `notesCard`/`submitRow` ops land on the live ones. `add` replaces silently, so the first question loses its evidence.

```bash
# more.json uses the manifest schema below; only `questions` is read.
"$ATRIUM_CLI_PATH" note read "$NOTE_ID" > /tmp/canvas.json
python3 <skill-dir>/scripts/build_question_patches.py more.json \
  --append --canvas /tmp/canvas.json --patches-out /tmp/more.jsonl \
  && "$ATRIUM_CLI_PATH" note canvas-patch "$NOTE_ID" < /tmp/more.jsonl
```

`--append` reads the live canvas and emits ops for the new cards only. It inserts them before `notesCard` (else `submitRow`). On a `--tabs` canvas each card becomes a new tab, ahead of the Resolution tab. It seeds their state keys, and numbers counter keys past the canvas's highest. It refuses a question id already on the canvas and any op that would overwrite a live element or state key, so the user's answers so far stay. Give the new question the next free id (`q5_<topic>`). Daemon down: pass the note's `note.canvas.json` as `--canvas`. Tell the user in chat that a card was added.

## Manifest schema

```jsonc
{
  "title": "Decisions: repo-audit open questions (2026-07-02)",
  "intro": "Eight decisions from the audit. Recommendations pre-selected.",
  "provenance": "pane 29724c0c \"repo audit\" · session e93271… · source: repo-audit report · 2026-07-02",
  "notes_placeholder": "Overrides, constraints, things I got wrong…",
  "questions": [
    {
      "id": "q1_fixture",                       // state key = reply key
      "title": "1 — Scoring fixture DB for CI",
      "tab": "1 Fixture",                        // optional; --tabs label, defaults to "1 fixture" from the id
      "description": "Card subtitle (1 line).",
      "context": "Muted text above the options.",   // optional
      "notes_placeholder": "Notes / override for this decision…",  // optional; per-question notes box is always added
      "recommended": "synthetic",
      "options": [
        {"value": "synthetic", "label": "Synthetic generated fixture (recommended)"},
        {"value": "real", "label": "Real tracked fixture DB"}
      ],
      "checkbox": {"id": "q1_bundle", "label": "Also do X in same PR", "default": true},  // optional
      "grounding": [
        {"type": "text", "content": "Why this snippet matters…"},
        {"type": "code", "file": "tests/test_scoring_stability.py", "start": 14, "end": 21},
        {"type": "open", "file": "tests/test_scoring_stability.py"},
        {"type": "chart", "kind": "bar", "title": "Rows per source",   // data grounding
         "data": [{"name": "sam", "rows": 3159}, {"name": "faa", "rows": 412}],
         "query": "SELECT source, count(*) …", "provenance": "prod warehouse, 2026-07-02"},
        {"type": "image", "src": "data:image/png;base64,…", "alt": "score distribution"}
      ]
    }
  ]
}
```

`file` paths are resolved relative to `--repo` (default: cwd). The generator reads the real lines at build time — if the file moved, the build fails loudly instead of shipping stale snippets.

## Data grounding — when the question is a data question

If deciding requires knowing what the data actually looks like (distributions, counts, trends, thresholds), **pull real data from the authoritative store and chart it in the card**. A user staring at a bar chart of the actual score distribution makes a better cutoff decision than one reading your prose summary of it.

Rules:

1. **Query the authoritative/prod store, not a local copy** — follow the project's conventions for which store is truth (e.g. a serving DB on a prod host vs a stale local dev file). If project memory says "always check X not local", that applies here doubly.
2. **Load the `dataviz` skill BEFORE choosing chart form** — it governs form/color/labeling for any chart, including canvas `BarGraph`/`LineGraph`. For ideation on *which* visualization makes the decision legible (density, small multiples, data-ink), also consult `tufte-viz`.
3. **Native components first**: `chart` grounding items render as canvas `BarGraph`/`LineGraph` — theme-aware, zero extra tooling. Use them for ≤~30 categories/points.
4. **Rendered images for dense graphics**: when the decision needs a distribution with reference lines, small multiples, or anything BarGraph can't express, generate a PNG (matplotlib/tufte-viz principles), embed via an `image` grounding item as a base64 `data:` URI. Keep it under ~200KB (downsample; the canvas is a form, not a gallery).
5. **Always ship provenance**: every `chart`/`image` item should carry the exact `query` (rendered as a `Code` block under the chart) and a `provenance` line (store + as-of date). A chart the user can't trace is just prettier prose.
6. **Aggregate before you ship**: send GROUP BY results, never row dumps. The canvas payload lives in a note file on disk.

## Gotchas (each one cost a debugging round — don't rediscover them)

- **Generate patches with `json.dumps`, never hand-written heredocs**, the moment code snippets are involved — embedded quotes/newlines will corrupt hand-escaped JSONL. The generator script exists for this reason.
- **`canvas-patch` rejects piped-stdin + `--from-file` together.** In non-interactive shells stdin looks piped; feed the file via redirect: `canvas-patch "$NOTE_ID" < patches.jsonl`.
- **`$bindState` (render-time, two-way, input props) vs `$state` (action-time, read-only, action params).** Submit buttons use `{"$state": ""}`; inputs use `{"$bindState": "/key"}`. Mixing them is the #1 silent-no-op bug.
- **`atrium_command` params go in the URI query string**, URL-encoded — `atrium://commands/file.open?path=<urlencoded>` — never as sibling params.
- **Pre-seed recommendations in `/state`**, not just labels: an agreeing user should be able to hit Send untouched.
- **Open with `note open`, not `note new --open`** — both show the pane, but only `note open` takes `--split … --direction subtab`, and only `note open --json` returns the `paneId` you rename to the note title (see "Where the canvas opens"). Keep `--source agent` on `note new` either way, or the note can't be bulk-filtered. If `note open` fails because the app UI is down, the note already exists and is durable on disk: give the user its id and skip the pane rename. **Never retry with `note new --open`** — that creates a second note and invalidates the `$NOTE_ID` your patches and `--send-framing` point at.
- **Make the sub-tab with `note open --split`, not `pane create --type notepad --split`.** `pane create` makes an empty notepad, and no CLI loads a note into it afterwards (0.330.0, 2026-10-02). `note open --split` creates the pane and loads the note in one call.
- **Amend a Resolution by re-running `--resolution` against a fresh `note read`.** The script replaces `resolutionCard` and keeps one reference to it, under the heading. A stale `--canvas` file points the `remove` op at the wrong index. Before this fix the script appended the card after the provenance footer, and re-runs added a second card. A re-run moves an old bottom card to the top.
- **The submit Button can fail silently on SDK-transport panes** (`transportKind: claude-sdk` — the default for agent-chat panes): "Send to agent" needs a live PTY write generation, which these panes don't have, so it errors client-side before ever reaching the daemon (upstream bug, filed [jonnyasmar/atrium-issues#26](https://github.com/jonnyasmar/atrium-issues/issues/26)). **Not a dependency, just a convenience**: every canvas edit persists to `state.json` immediately, so if the user reports a Send error, tell them to say "done" and read their answers from `state.json` in the note dir (`~/.atrium/notes/<workspace>/<folder>/<note-id>/state.json`) instead of waiting on the reply turn. Run the checks in "Answers read from disk" first: a missing or seed-equal `state.json` can be your own defaults echoed back. Not `atrium note read <id> --json`: it returns `note.canvas.json`, whose `state` is still the seed — your pre-selected recommendations, with every user note empty (verified 2026-09-23: a user's `option_b` read back as the seeded `option_a`). Confirmed working around it twice on real canvases (2026-07-30/31) before this was root-caused.
- **If the atrium daemon itself is down** (`canvas-patch`/any `atrium note …` call fails with "Transport error" / IPC or `stable.sock` connection refused — not the SDK-transport Send-button case above, the whole daemon is unreachable), don't block on it. Note files live at `~/.atrium/notes/<workspace>/<folder>/<note-id>/note.canvas.json`; apply your RFC-6902 patch ops to that file directly. Safe specifically *because* the daemon is down — nothing else can race the write while it's unreachable. Once the daemon recovers, re-verify with the step 6 readback (`note read`, not `note show`). Hit 3+ times live (2026-08-05/06/07) before being folded in here; each time it was re-derived from scratch instead of looked up.

## Answers read from disk: prove the user touched the canvas

A reply turn proves the user acted. A disk read does not. You pre-seeded every recommendation, so a `state.json` equal to the seed can be your own defaults. Acting on it executes decisions the user never made. Before you act on a disk read:

1. **Find the note dir by the full note id.** `find "${ATRIUM_DATA_DIR:-$HOME/.atrium}/notes" -type d -name "$NOTE_ID"` must print exactly one path. Note ids are UUIDv7, so notes made in the same minute share their leading segments. A prefix match (`-path '*01a0168e*'`) once returned note `01a0168e-eff0…` for `01a0168e-eec7…`, with that note's unrelated `{"choice":"skip"}` state (2026-08-19).
2. **Get the verdict.** `python3 <skill-dir>/scripts/decision_index.py --json | jq -r --arg id "$NOTE_ID" '.canvases[] | select(.id == $id) | .answer_evidence'` applies these rules. Add `--workspace <id>` when the note lives in another workspace; the id is the path segment after `notes/`.

| `answer_evidence` | Rule | Meaning |
|---|---|---|
| `no-state` | no `state.json` | Untouched. atrium 0.352.0 writes the file on the first user edit. 58 of 112 canvases made since 2026-10-08 have none. |
| `edited` | a value or note differs from the seed (`.state` in `note.canvas.json`) | Answered. |
| `seed-unconfirmed` | equals the seed | Unanswered. A legacy renderer can write the seed on first render, including long after creation; copied or restored state is also indistinguishable from acceptance. |

3. **Safe default: `no-state` or `seed-unconfirmed` means UNANSWERED.** Do not execute the pre-seeded values. Re-surface the canvas: name the note and its pane, say it shows no answers, and ask the user to fill it in or explicitly confirm the defaults. A reply turn or submission is evidence of that confirmation; file mtimes are not.

Compare against `createdAt` inside `meta.json`, never against the `meta.json` mtime. Every `canvas-patch` rewrites `meta.json`. On 2026-10-28, 426 of 477 canvases had a `meta.json` mtime that differed from `createdAt`. `viewport.json` changes when the user opens or scrolls the note. It shows the canvas was seen, not answered: 30 canvases have a `viewport.json` and no `state.json`.

## After the reply

The payload mirrors the state you bound — one `{qid}` per answer, one `{qid}_notes` per question (empty string if the user left it blank), plus the global `notes`. On receipt: (1) restate each decision in one line, **reading each `{qid}_notes` — a per-question note can qualify or override the radio choice for that decision** (e.g. "yes but only for prod" narrows the approval; "recommended is wrong because…" flips it); never act on the radio value while ignoring a note that contradicts it, (2) act (file beads/tasks, run the approved checks, start the approved work), (3) if any answer contradicts something you shipped earlier (a report, a plan), update that artifact — the plan is what future sessions read, (4) **always patch a Resolution card into the canvas** (per "Naming & provenance") before ending the turn: chosen answers + outcomes (tracker IDs, commits, verification results), patched in at the top via `canvas-patch`, so the note stands alone as the decision record.

**Write the Resolution for someone who opens the canvas cold.** They read the top card and nothing else:

- **Title** states the result: `✅ RESOLVED — <topic>`, or `✅ SUPERSEDED — <why>` when the questions were mooted.
- **Description** gives the tally in one line: `4/4 recommendations accepted, executed same session`.
- **Decision** names the option in words. Pass `qid` and the raw value, and the script swaps in the label the user clicked. `close_all` in a table cell means nothing to a reader.
- **Outcome** gives the result in one line, ideally under 200 characters: what changed, tracker ID or PR, verified or not. Put a longer story in `summary`, not in a table cell.
- **Overrides are visible.** When a per-question note changed the decision, say so in the outcome: `Override (note): fix now, not after sign-ups`.

Use the script (`build_question_patches.py --resolution --canvas`) for every Resolution. It needs no hand-escaping, and it places the card. For a narrative outcome (questions mooted, one decision reframed the rest), set `title` and `summary` and leave `items` empty.

Hand-author a card only when the script cannot express the outcome. Then you own what the script does: emit the ops with `json.dumps` (never heredocs — gotcha #1), use unique element keys prefixed `resolution*`, insert the card into the root's `children` at the index after the heading and intro (never `children/-`), or into the Resolution tab's panel on a tabbed canvas, prefix the heading text with `✅`, and relabel the `send_to_agent` button. **Never reuse a question's `txt_N`/`code_N`/`qN_*` key**, or the `add` op silently overwrites that question's evidence.

The `--resolution` manifest is a small JSON object (not the question manifest); every field is optional:

```jsonc
{
  "title": "✅ RESOLVED — scoring fixture (2026-07-07)",  // optional; defaults to "Resolution"
  "description": "8/8 recommendations accepted, executed same session.",  // optional
  "summary": "One-line what-happened (optional narrative above the table).",
  "date": "2026-07-07",                                   // optional; description fallback
  "items": [
    // qid fills `question` from the card title and maps `decision` to the option label
    {"qid": "q1_fixture", "decision": "synthetic", "outcome": "bd-cor34 created, commit abc123, CI green"},
    {"question": "Follow-up raised in notes", "decision": "Deferred", "outcome": "bd-xyz12 filed"}
  ]
}
```

**This applies to whichever session parses the reply.** If the canvas was created by a calling agent session and control has since passed back to you, you still own the Resolution patch — and you don't need to have created the canvas to find it. The default `--send-framing` above embeds `{noteId}`, so the reply itself names the note to patch: pull the id straight from the framed turn and `canvas-patch` the Resolution in. (Only if the canvas was created with a framing that omitted `{noteId}` do you fall back to recovering the id by title: `"$ATRIUM_CLI_PATH" note list --folder decisions --json`, match the `{noteTitle}` the reply carries, or filter by the tracker-id tag.) The decision is not "done" until the Resolution card is in the note.

## Index, vault export & lifecycle (so the pile stays organized)

Canvases accumulate one per decision batch. Creation-time naming (above) makes each one findable; `scripts/decision_index.py` keeps the *set* organized. Run it after patching a Resolution, and let `atrium-workspace-sweep` run it on every sweep.

```bash
S=<skill-dir>/scripts/decision_index.py
python3 "$S"                                   # print the markdown index (read-only)
python3 "$S" --upsert-note                     # create/update the `Decisions: INDEX` note in folder `decisions`
python3 "$S" --export-vault "${AGENT_VAULT_PATH:-$HOME/obsidian/agent-journal}"   # one ADR .md per canvas + _index.md
python3 "$S" --sweep-report --export-vault "$VAULT"   # lifecycle tiers, never deletes
python3 "$S" --json                            # raw scan (questions, chosen answers, resolution rows, trackers)
```

What it reads: `meta.json` + `note.canvas.json` + `state.json` on disk under `$ATRIUM_DATA_DIR/notes/<workspace>/decisions/` (the CLI's `note list --json` omits `folder` and ISO timestamps, so disk is the source). Answers and notes come from `state.json`, which the UI writes on every edit; the `state` in `note.canvas.json` is only the seed and fills keys the user never touched. Also scans the workspace root for `Decisions:`-titled notes outside the folder and reports them as **misfiled**.

Status per canvas: `resolved` (has a `resolution*` Card or a `✅` Card) · `answered` (`answer_evidence` is `edited`, no Resolution card — a half-record, see "After the reply") · `open` (no answers, or only the seed: `no-state` / `seed-unconfirmed`, see "Answers read from disk").

Vault export: `<vault>/decisions/<date>-<topic-slug>-<id8>.md`, frontmatter carries `atrium_note_id`, `status`, `trackers`; body = questions + chosen option + notes, Resolution table, provenance. Idempotent (unchanged bodies are not rewritten). The atrium note is authoritative while it exists; the vault copy is the durable ADR once the note is archived. Default vault: the agent-journal (`$AGENT_VAULT_PATH`) — decision records are agent-session artifacts, not human-curated project specs.

Lifecycle tiers (`--sweep-report`; every action is ask-first):

| Tier | Rule | Action |
|---|---|---|
| `misfiled` | `Decisions:` title, not in `decisions/` | move the note dir under `decisions/` (folder = directory layout) |
| `stale-open` | not resolved, untouched ≥ `--stale-days` (30), and a real open question | patch a Resolution, or resolve as "abandoned" |
| `background-work` | watch/monitor/loop pane — 🔁👀⏳🎯 title, watch wording, or a canvas with no question elements | reclassify; there is no decision to resolve |
| `duplicate` | same title *and* date as a newer canvas | keep one, delete the other |
| `not-a-canvas` | no `note.canvas.json` (html note) | read by hand — the sweep cannot see questions or Resolution |
| `unexported` | no vault file | `--export-vault` |
| `archivable` | resolved ≥ `--archive-days` (90) ago AND vault copy exists | `atrium note delete <id> --confirm` |

Never delete a canvas without a vault copy; the sweep tier only appears once the export exists.
