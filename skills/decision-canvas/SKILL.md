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
6. **A Resolution card — always, once the reply comes back.** The canvas is not complete until the session that receives the reply patches a `Resolution` card in (chosen answer + outcome per question). This is mandatory, not a nicety, and it holds **even when the canvas was passed back to a calling agent session** — whichever session parses the reply owns the resolution patch (see "After the reply"). A canvas with answers but no Resolution card is an unfinished decision record.

State keys ARE the reply schema: name them `q1_<topic>`, `q2_<topic>`, … so the returned JSON parses on sight.

## Naming & provenance (so canvases are findable later)

Decision canvases accumulate; an ad-hoc title ("Audit: open questions") is unfindable in a month. Every canvas MUST be created with:

- **Title**: `Decisions: <topic> (<YYYY-MM-DD>)` — e.g. `Decisions: repo-audit open questions (2026-07-02)`. The `Decisions:` prefix makes the whole family one search away; the date disambiguates recurring topics (grooming, sprint reviews).
- **Folder**: `--folder decisions` — groups all decision canvases under one node in the notes tree instead of scattering them through the workspace root.
- **Tags**: `--tags decision,<topic-slug>,<tracker-ids>` — include the bead/PR/task IDs the decisions concern (e.g. `decision,repo-audit,bd-cor34`). Tags are searchable; tracker IDs make the canvas discoverable from the ticket side.
- **Provenance footer**: set `provenance` in the manifest (rendered as a muted footer line) with the calling pane (id + name), the session id, the driving artifact, and the date — e.g. `pane 29724c0c "Canvas subtab link" · session e93271… · source: repo-audit report · 2026-07-02`. `meta.json` records which pane authored the note, but panes die with sessions; the footer is the durable tie. Name the pane, not just the id — ids are unreadable in a room full of canvases.

## Where the canvas opens — tie it to the calling pane

A canvas that appears with no visible link to the session that asked for it is a puzzle: with several agents running, the user cannot tell which pane wants which answer. The link is the pane name. The first character of that name is the status.

**Subtab, verified atrium 0.330.0 on 2026-10-02.** `pane create --type notepad --split "$ATRIUM_PANE_ID" --direction subtab` succeeds and groups the new notepad under the caller. The 0.321.0 failure (`unsupported pane type: notepad`, expected terminal or browser) is stale. The new notepad stays empty. `note open` and `notepad.open` always mint a new row-sibling in the active room. They ignore `targetPaneId` and `paneId`. No CLI writes `notepad-state.currentNoteId`. There is no `pane move`, so a loaded notepad cannot join the caller's tab group afterwards. Do not create the empty subtab. You get a blank tab plus the sibling canvas. Keep the sibling `note open` below until atrium can load a note into an existing notepad.

**Status glyph.** Notepad `favicon` stays null. No CLI sets it. Favicon is a browser-pane signal. Put status in the first character of the pane name:

- Needs a decision, or the Resolution card is not in yet: `● Decisions ← <your pane name>`
- Resolution card patched: `✅ Decisions ← <same rest of the name>`

The note title stays `Decisions: <topic> (YYYY-MM-DD)`. Do not put `●` or `✅` in the title. `decision_index.py` treats a Card whose title starts with `✅` as resolved. A pane rename does not change that. Keep the pane name under ~30 characters.

`note open` lands in the caller's room as a sibling. Atrium composes the room label from the pane names (`<agent pane> w/ Notes`, then `<agent pane> & <note pane>` once both are named). Both names must stay meaningful.

Two renames on open, both mandatory:

1. **Your own pane first.** If it still carries a launcher default, rename it to a 10–20 char work description before opening the canvas. The room label inherits it.
2. **The notepad, right after opening** — `● Decisions ← <your pane name>`. `note open --json` returns the `paneId`. `note new --open` does not, which is why the workflow below splits create from open.

After opening, confirm the notepad pane's room matches yours (`pane list --json`). If the user switched rooms mid-flight it can land elsewhere. Rename it regardless, and say in chat where it went.

**Close the loop after acting — always**: once decisions come back and you've executed them, you MUST patch a `Resolution` card into the canvas (chosen answer per question + what you did: tracker IDs created/updated, commits, verification results). In the same turn, rename that notepad from `●` to `✅` when the pane still exists. The canvas then reads as a complete decision record, and the tab no longer asks for attention. This step is non-optional. It fires even when another session created the canvas. The session holding the reply patches the Resolution and flips the glyph before its turn ends. Skipping either leaves a half-record that still looks open.

## Workflow

```bash
# 1. Build a manifest (see schema below) describing questions + grounding.
#    Snippets/queries are resolved AT BUILD TIME from real files/data — never paste code by hand.
# 2. Generate skeleton + patches:
python3 <skill-dir>/scripts/build_question_patches.py manifest.json \
  --skeleton-out /tmp/spec.json --patches-out /tmp/patches.jsonl

# 3. Name YOUR pane before the canvas opens — the room label inherits it, and
#    that label is what ties canvas to caller. Substitute a real 10-20 char
#    description for the placeholder; no script can invent one for you.
read_pane_name() {
  "$ATRIUM_CLI_PATH" pane list --json | jq -r --arg me "$ATRIUM_PANE_ID" \
    '.[] | select(.id == $me) | .name'
}
CALLER=$(read_pane_name)
case "$CALLER" in
  ""|claude-code|codex|gemini|cursor-agent)
    "$ATRIUM_CLI_PATH" pane rename "$ATRIUM_PANE_ID" --name "<10-20 char work desc>"
    CALLER=$(read_pane_name) ;;
esac

# 4. Create the note, then open it (separately — `note open --json` returns the
#    pane id, `note new --open` does not). Title/folder/tags per
#    "Naming & provenance" below — non-optional.
NOTE_ID=$("$ATRIUM_CLI_PATH" note new --type canvas \
  --title "Decisions: <topic> ($(date +%F))" \
  --folder decisions --tags "decision,<topic-slug>,<tracker-ids>" \
  --source agent \
  --send-framing "Decisions (canvas '{noteTitle}', note {noteId}):\n\n{payload}" \
  --spec /tmp/spec.json --json | jq -r '.meta.id // .id')
NOTE_PANE=$("$ATRIUM_CLI_PATH" note open "$NOTE_ID" --json | jq -r '.paneId')
# First character is the status. ● = needs attention. ✅ = Resolution card is in.
# Do not create a notepad subtab first: it stays empty (see "Where the canvas opens").
"$ATRIUM_CLI_PATH" pane rename "$NOTE_PANE" --name "● Decisions ← $CALLER"
"$ATRIUM_CLI_PATH" note canvas-patch "$NOTE_ID" < /tmp/patches.jsonl

# 5. End your turn. The reply arrives as a framed user turn when they hit Send.
#    Parse the state JSON, act on each decision, confirm what you did.

# 6. ALWAYS close the loop: after acting, patch a Resolution card into the SAME note
#    (script path below for a per-question tally; hand-author a richer card for a
#    narrative outcome — see "After the reply"). Write a resolution manifest
#    {title?, summary?, date, items:[{question, decision, outcome}]}, then emit +
#    apply resolution-only ops (--resolution skips the skeleton):
python3 <skill-dir>/scripts/build_question_patches.py resolution.json \
  --resolution --patches-out /tmp/resolution.jsonl
"$ATRIUM_CLI_PATH" note canvas-patch "$NOTE_ID" < /tmp/resolution.jsonl
# Flip the tab in the same turn. A later session has no $NOTE_PANE: if exactly
# one pane is named "● Decisions ← …", rename that one to the ✅ form. Zero or
# several matches: skip, and say so. Never retitle a neighbor.
if [ -z "${NOTE_PANE:-}" ]; then
  # Later session: set CALLER from the note provenance footer, not this pane.
  MATCHES=$("$ATRIUM_CLI_PATH" pane list --json | jq --arg caller "$CALLER" \
    '[.[] | select(.name == ("● Decisions ← " + $caller))]')
  case "$(jq 'length' <<<"$MATCHES")" in
    1) NOTE_PANE=$(jq -r '.[0].id' <<<"$MATCHES") ;;
    *) printf 'Canvas pane match is zero or ambiguous; leaving status unchanged.\n' >&2 ;;
  esac
fi
if [ -n "${NOTE_PANE:-}" ]; then
  "$ATRIUM_CLI_PATH" pane rename "$NOTE_PANE" --name "✅ Decisions ← $CALLER"
fi
#    $NOTE_ID is the note the canvas already lives in. Cross-session, the reply's
#    framing carries {noteId} — read it from there (fallback: note list --folder).
```

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
- **Open with `note open`, not `note new --open`** — both show the pane, but only `note open --json` returns the `paneId`, and without that id you cannot rename the pane to name its caller (see "Where the canvas opens"). Keep `--source agent` on `note new` either way, or the note can't be bulk-filtered. If `note open` fails because the app UI is down, the note already exists and is durable on disk: give the user its id and skip the pane rename. **Never retry with `note new --open`** — that creates a second note and invalidates the `$NOTE_ID` your patches and `--send-framing` point at.
- **Do not open the canvas as a subtab.** On atrium 0.330.0 the notepad subtab creates, and it stays empty. `note open` still adds a sibling and ignores a target pane id (verified 2026-10-02). An empty subtab is junk. Status is the first character of the pane name (`●` until the Resolution rename, then `✅`). Favicon stays null on notepads.
- **Patch the Resolution card exactly once.** `--resolution` uses fixed element keys, so re-running it replaces the card's *contents* but appends a **second** `resolutionCard` reference to `rootStack` — a duplicate card. Build the full resolution in one manifest and patch it once; to amend, edit the note in place rather than re-running `--resolution`.
- **The submit Button can fail silently on SDK-transport panes** (`transportKind: claude-sdk` — the default for agent-chat panes): "Send to agent" needs a live PTY write generation, which these panes don't have, so it errors client-side before ever reaching the daemon (upstream bug, filed [jonnyasmar/atrium-issues#26](https://github.com/jonnyasmar/atrium-issues/issues/26)). **Not a dependency, just a convenience**: every canvas edit persists to `state.json` immediately, so if the user reports a Send error, tell them to say "done" and read their answers from `state.json` in the note dir (`~/.atrium/notes/<workspace>/<folder>/<note-id>/state.json`) instead of waiting on the reply turn. Not `atrium note read <id> --json`: it returns `note.canvas.json`, whose `state` is still the seed — your pre-selected recommendations, with every user note empty (verified 2026-09-23: a user's `option_b` read back as the seeded `option_a`). Confirmed working around it twice on real canvases (2026-07-30/31) before this was root-caused.
- **If the atrium daemon itself is down** (`canvas-patch`/any `atrium note …` call fails with "Transport error" / IPC or `stable.sock` connection refused — not the SDK-transport Send-button case above, the whole daemon is unreachable), don't block on it. Note files live at `~/.atrium/notes/<workspace>/<folder>/<note-id>/note.canvas.json`; apply your RFC-6902 patch ops to that file directly. Safe specifically *because* the daemon is down — nothing else can race the write while it's unreachable. Re-verify with `atrium note read <id> --json` once the daemon recovers (there is no `note show`). Hit 3+ times live (2026-08-05/06/07) before being folded in here; each time it was re-derived from scratch instead of looked up.

## After the reply

The payload mirrors the state you bound — one `{qid}` per answer, one `{qid}_notes` per question (empty string if the user left it blank), plus the global `notes`. On receipt: (1) restate each decision in one line, **reading each `{qid}_notes` — a per-question note can qualify or override the radio choice for that decision** (e.g. "yes but only for prod" narrows the approval; "recommended is wrong because…" flips it); never act on the radio value while ignoring a note that contradicts it, (2) act (file beads/tasks, run the approved checks, start the approved work), (3) if any answer contradicts something you shipped earlier (a report, a plan), update that artifact — the plan is what future sessions read, (4) **always patch a Resolution card into the canvas** (per "Naming & provenance") before ending the turn: chosen answers + outcomes (tracker IDs, commits, verification results), appended via `canvas-patch`, so the note stands alone as the decision record, (5) **rename the canvas pane** from `● Decisions ← …` to `✅ Decisions ← …` in that same turn when the pane still exists. You created it: you still have `$NOTE_PANE`. A later session: `pane list --json`, and rename only when exactly one pane name starts with `● Decisions ← `. Several matches: use the caller named in the provenance footer. Still ambiguous: skip the rename and say so.

Two ways to build the Resolution patch — both fine, pick by shape:

- **Script path (`build_question_patches.py --resolution`)** — reliable, no hand-escaping, renders a question/decision/outcome `Table`. Best when the resolution is a clean per-question tally.
- **Hand-authored card** — a richer narrative card (superseding title like `✅ RESOLVED — scope corrected`, a framing description, prose body) when the outcome isn't a tidy table (e.g. the questions were mooted, or one decision reframed the rest). Most real resolutions take this shape. If you hand-author: emit the ops with `json.dumps` (never heredocs — gotcha #1), and **use unique element keys prefixed `resolution*` — never reuse a question's `txt_N`/`code_N`/`qN_*` key, or the `add` op silently overwrites that question's evidence.** (This is exactly the collision the `--resolution` script now guards against.)

The `--resolution` manifest is a small JSON object (not the question manifest); `title`/`description`/`summary` are optional:

```jsonc
{
  "title": "✅ RESOLVED — scoring fixture (2026-07-07)",  // optional; defaults to "Resolution"
  "description": "8/8 recommendations accepted, executed same session.",  // optional
  "summary": "One-line what-happened (optional narrative above the table).",
  "date": "2026-07-07",                                   // optional; description fallback
  "items": [
    {"question": "1 — Scoring fixture DB", "decision": "Synthetic", "outcome": "bd-cor34 created, commit abc123, CI green"}
  ]
}
```

**This applies to whichever session parses the reply.** If the canvas was created by a calling agent session and control has since passed back to you, you still own the Resolution patch — and you don't need to have created the canvas to find it. The default `--send-framing` above embeds `{noteId}`, so the reply itself names the note to patch: pull the id straight from the framed turn and `canvas-patch` the Resolution in. (Only if the canvas was created with a framing that omitted `{noteId}` do you fall back to recovering the id by title: `"$ATRIUM_CLI_PATH" note list --folder decisions --json`, match the `{noteTitle}` the reply carries, or filter by the tracker-id tag.) The decision is not "done" until the Resolution card is in the note and, when the pane still exists, its name starts with `✅`.

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

Status per canvas: `resolved` (has a `resolution*` Card or a `✅` Card) · `answered` (state has chosen values, no Resolution card — a half-record, see "After the reply") · `open` (no answers).

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
