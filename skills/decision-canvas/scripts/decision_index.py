#!/usr/bin/env python3
"""Index, export and lifecycle-classify atrium decision canvases.

Reads every canvas under `<notes-root>/<workspace>/decisions/` straight from disk
(meta.json + note.canvas.json — the CLI list omits `folder` and ISO timestamps),
plus any root-level note whose title starts with `Decisions:` (misfiled).

Outputs (all optional, combinable):
  --index-out FILE     markdown index (default: stdout when nothing else asked)
  --upsert-note        create/update the `Decisions: INDEX` markdown note in the
                       `decisions` folder via the atrium CLI
  --export-vault DIR   one ADR-style markdown per canvas under DIR/decisions/
                       plus DIR/decisions/_index.md (idempotent: unchanged
                       bodies are not rewritten)
  --sweep-report       tier table for atrium-workspace-sweep (stale-open,
                       background-work, duplicate, not-a-canvas, misfiled,
                       unexported, archivable). Never deletes.
  --json               machine-readable dump of the scan

Status rule: a canvas is RESOLVED when it contains an element whose id starts
with `resolution` or whose Card title starts with `✅`. Everything else is OPEN.
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

INDEX_TITLE = "Decisions: INDEX"
TITLE_RE = re.compile(r"^Decisions:\s*(?P<topic>.*?)\s*\((?P<date>\d{4}-\d{2}-\d{2})\)\s*$")
# A tag is a tracker id when it carries a digit (bead bd-cor34, todoist 16-char ids,
# atrium-issues-16, pr278, TEAM-12). Digit-free tags are topic slugs.
TRACKER_RE = re.compile(r"^(?=.*\d)[A-Za-z0-9][A-Za-z0-9._#-]{3,}$")
SKIP_TAGS = {"decision", "decisions", "index"}


def die(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def atrium_cli() -> str:
    """Resolve the atrium binary: $ATRIUM_CLI_PATH must be an existing executable, else PATH lookup."""
    cand = os.environ.get("ATRIUM_CLI_PATH")
    if cand:
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
        die(f"ATRIUM_CLI_PATH is not an executable file: {cand}")
    found = shutil.which("atrium")
    if not found:
        die("atrium CLI not found (set ATRIUM_CLI_PATH or add atrium to PATH)")
    return found


def atrium(*args: str, stdin: str | None = None) -> str:
    cli = atrium_cli()
    r = subprocess.run([cli, *args], capture_output=True, text=True, input=stdin, timeout=60)
    if r.returncode != 0:
        die(f"{cli} {' '.join(args)}: {r.stderr.strip() or r.stdout.strip()}")
    return r.stdout


def resolve_workspace(explicit: str | None) -> str:
    if explicit:
        return explicit
    env = os.environ.get("ATRIUM_WORKSPACE_ID")
    if env:
        return env
    try:
        ctx = json.loads(atrium("context", "--json"))
        ws = ctx.get("workspaceId")
        if ws:
            return ws
    except SystemExit:
        pass
    die("cannot resolve workspace id: pass --workspace or set ATRIUM_WORKSPACE_ID")
    return ""  # unreachable


def slugify(text: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return s[:60] or "untitled"


def parse_iso(s: str | None) -> dt.datetime | None:
    if not s:
        return None
    try:
        d = dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None
    return d if d.tzinfo else d.replace(tzinfo=dt.timezone.utc)  # naive → UTC so arithmetic with aware `now` works


def _descendant_ids(elements: dict, root: str | None) -> list[str]:
    """Ids under `root` in child order, depth-first. Cycle- and typo-safe."""
    if not root:
        return []
    out: list[str] = []
    seen = {root}
    stack = list(reversed((elements.get(root, {}) or {}).get("children", []) or []))
    while stack:
        eid = stack.pop()
        if not isinstance(eid, str) or eid in seen or eid not in elements:
            continue
        seen.add(eid)
        out.append(eid)
        stack.extend(reversed((elements.get(eid, {}) or {}).get("children", []) or []))
    return out


def load_canvas(note_dir: Path) -> dict | None:
    meta_p = note_dir / "meta.json"
    if not meta_p.exists():
        return None
    try:
        meta = json.loads(meta_p.read_text())
        body_p = note_dir / "note.canvas.json"
        body = json.loads(body_p.read_text()) if body_p.exists() else {}
        state_p = note_dir / "state.json"
        live_state = json.loads(state_p.read_text()) if state_p.exists() else {}
    except (json.JSONDecodeError, OSError) as e:
        print(f"warn: skipping {note_dir.name}: {e}", file=sys.stderr)
        return None
    elements: dict = body.get("elements", {}) or {}
    # The canvas UI writes every edit to state.json. The `state` inside
    # note.canvas.json is the seed (the pre-selected recommendations) and never
    # moves, so reading it alone reports the recommendation as the answer and
    # drops every user note. Measured 2026-09-23 over one workspace's 193
    # canvases: reading state.json changed 45 answers and 27 notes in 44 of
    # them. Live wins; the seed fills keys the user never touched.
    state: dict = {**(body.get("state", {}) or {}), **(live_state if isinstance(live_state, dict) else {})}

    title = meta.get("title", "")
    m = TITLE_RE.match(title)
    topic = m.group("topic") if m else title.removeprefix("Decisions:").strip()
    date = m.group("date") if m else (meta.get("createdAt") or "")[:10]

    tags = meta.get("tags") or []
    if isinstance(tags, str):
        tags = [t for t in tags.split(",") if t]
    trackers = [t for t in tags if t not in SKIP_TAGS and TRACKER_RE.match(t)]
    topics = [t for t in tags if t not in SKIP_TAGS and t not in trackers]

    # questions: Card elements whose id ends in _card and starts with q<N>
    questions = []
    for eid, el in sorted(elements.items()):
        if not re.match(r"^q\d+_.*_card$", eid) or el.get("type") != "Card":
            continue
        key = eid[: -len("_card")]
        radio = elements.get(f"{key}_radio", {}).get("props", {})
        labels = {o.get("value"): o.get("label") for o in radio.get("options", []) if isinstance(o, dict)}
        chosen = state.get(key)
        questions.append(
            {
                "key": key,
                "title": el.get("props", {}).get("title", key),
                "description": el.get("props", {}).get("description", ""),
                "chosen": chosen,
                "chosen_label": labels.get(chosen, chosen),
                "notes": state.get(f"{key}_notes", "") or "",
            }
        )

    # A Text element is resolution evidence too. Agents have patched
    # `resolution_card` in as a bare Text since at least 2026-07-09; a
    # Card-only rule reports those canvases unresolved for ever, so the
    # sweep keeps proposing a Resolution card that is already there.
    # Card still wins when both exist — it carries the title/description.
    resolution = None
    card_id = None
    for eid, el in elements.items():
        props = el.get("props", {}) or {}
        if eid.lower().startswith("resolution") and el.get("type") == "Card":
            resolution = {"title": props.get("title", "Resolution"), "description": props.get("description", ""), "rows": []}
            card_id = eid
        elif el.get("type") == "Card" and str(props.get("title", "")).startswith("✅"):
            resolution = {"title": props.get("title"), "description": props.get("description", ""), "rows": []}
            card_id = eid
    if resolution is None:
        for eid, el in elements.items():
            if eid.lower().startswith("resolution") and el.get("type") == "Text":
                resolution = {"title": "Resolution", "description": "", "rows": []}
                break
    if resolution is not None:
        # The prose lives in the card's children. Agents name them freely
        # (`res_q1`, `exec_log`), so an id-prefix rule drops the lot and the
        # export renders a one-line stub — then reports it `unchanged`,
        # because the body it hashes never saw the content (#435).
        # Walk children first, then keep the flat `resolution*` convention
        # for the ~190 canvases written before cards were nested. Several
        # flat Texts now join in id order; the old code assigned `summary`,
        # so one of them won by dict order. Across 484 local canvases that
        # change gained content on 21 and lost none.
        text_ids = [i for i in _descendant_ids(elements, card_id) if elements.get(i, {}).get("type") == "Text"]
        text_ids += sorted(
            eid
            for eid, el in elements.items()
            if eid.lower().startswith("resolution") and el.get("type") == "Text" and eid not in text_ids
        )
        chunks = []
        for eid in text_ids:
            content = ((elements.get(eid, {}).get("props") or {}).get("content") or "").strip()
            if content:
                chunks.append(content)
        if chunks:
            resolution["summary"] = "\n\n".join(chunks)
        for eid, el in elements.items():
            if eid.lower().startswith("resolution") and el.get("type") == "Table":
                resolution["rows"] = (el.get("props") or {}).get("rows", []) or []

    provenance = ""
    for eid, el in elements.items():
        if "provenance" in eid.lower() and el.get("type") == "Text":
            provenance = (el.get("props", {}) or {}).get("content", "")

    answered = any(q["chosen"] not in (None, "") for q in questions)
    return {
        "id": meta.get("id", note_dir.name),
        "title": title,
        "topic": topic,
        "date": date,
        "folder": meta.get("folder", ""),
        "type": meta.get("type"),
        "tags": tags,
        "topics": topics,
        "trackers": trackers,
        "created": meta.get("createdAt"),
        "updated": meta.get("updatedAt"),
        "origin_pane": meta.get("originAgentPaneId"),
        "questions": questions,
        "answered": answered,
        "resolution": resolution,
        "status": "resolved" if resolution else ("answered" if answered else "open"),
        "provenance": provenance,
        "general_notes": state.get("notes", "") or "",
        "path": str(note_dir),
        "has_canvas": body_p.exists(),
    }


def scan(notes_root: Path, workspace: str) -> tuple[list[dict], list[dict]]:
    ws_dir = notes_root / workspace
    if not ws_dir.is_dir():
        die(f"workspace notes dir not found: {ws_dir}")
    canvases: list[dict] = []
    misfiled: list[dict] = []
    dec_dir = ws_dir / "decisions"
    if dec_dir.is_dir():
        for d in sorted(dec_dir.iterdir()):
            if d.is_dir() and (c := load_canvas(d)):
                if c["title"] == INDEX_TITLE:
                    continue
                canvases.append(c)
    for d in sorted(ws_dir.iterdir()):
        if not d.is_dir() or d.name == "decisions":
            continue
        meta_p = d / "meta.json"
        if not meta_p.exists():
            continue
        try:
            title = json.loads(meta_p.read_text()).get("title", "")
        except (json.JSONDecodeError, OSError) as e:
            print(f"warn: skipping {d.name}: {e}", file=sys.stderr)
            continue
        if title.startswith("Decisions:") and title != INDEX_TITLE:
            if c := load_canvas(d):
                misfiled.append(c)
    key = lambda c: (c["date"] or "", c["created"] or "")  # noqa: E731
    canvases.sort(key=key, reverse=True)
    misfiled.sort(key=key, reverse=True)
    return canvases, misfiled


# ---------- renderers ----------


def md_escape(s: str) -> str:
    return str(s).replace("|", "\\|").replace("\n", " ").strip()


def render_index(canvases: list[dict], misfiled: list[dict], today: str, vault_dir: Path | None) -> str:
    counts = {"resolved": 0, "answered": 0, "open": 0}
    for c in canvases:
        counts[c["status"]] += 1
    lines = [
        f"# {INDEX_TITLE}",
        "",
        f"Auto-generated by decision-canvas/scripts/decision_index.py on {today}. Do not hand-edit; re-run instead.",
        "",
        f"**{len(canvases)} canvases** · {counts['resolved']} resolved · {counts['answered']} answered-unresolved · {counts['open']} open"
        + (f" · {len(misfiled)} misfiled (not in `decisions` folder)" if misfiled else ""),
        "",
    ]
    open_ones = [c for c in canvases if c["status"] != "resolved"]
    if open_ones:
        lines += ["## Needs attention", ""]
        for c in open_ones:
            why = "answered but no Resolution card" if c["status"] == "answered" else "no answers yet"
            lines.append(f"- **{c['title']}** — {why} · `{c['id'][:8]}`")
        lines.append("")
    lines += ["## All canvases", "", "| Date | Topic | Status | Qs | Trackers | Note |", "|---|---|---|---|---|---|"]
    for c in canvases:
        status = {"resolved": "✅ resolved", "answered": "🟡 answered", "open": "⬜ open"}[c["status"]]
        lines.append(
            f"| {c['date']} | {md_escape(c['topic'])} | {status} | {len(c['questions'])} | "
            f"{md_escape(', '.join(c['trackers']) or '—')} | `{c['id'][:8]}` |"
        )
    if misfiled:
        lines += ["", "## Misfiled (root folder, should be `decisions`)", ""]
        for c in misfiled:
            lines.append(f"- {c['title']} · `{c['id'][:8]}` — move dir under `decisions/` (folder = directory layout)")
    if vault_dir:
        lines += ["", f"Vault export: `{vault_dir}` (one file per canvas, `_index.md` there mirrors this table)."]
    lines += ["", "Open a canvas: `atrium note open <id>`. Rebuild this index: `python3 <skill>/scripts/decision_index.py --upsert-note`."]
    return "\n".join(lines) + "\n"


def render_adr(c: dict, workspace: str) -> str:
    fm = {
        "title": c["title"],
        "date": c["date"],
        "status": c["status"],
        "atrium_note_id": c["id"],
        "atrium_workspace": workspace,
        "tags": ["decision-canvas", *c["topics"]],
        "trackers": c["trackers"],
        "source": "atrium decision canvas (decision-canvas skill)",
    }
    out = ["---"]
    for k, v in fm.items():  # every scalar JSON-quoted: a JSON string is a valid YAML double-quoted scalar
        if isinstance(v, list):
            out.append(f"{k}: []" if not v else f"{k}:")
            out += [f"  - {json.dumps(str(x), ensure_ascii=False)}" for x in v]
        else:
            out.append(f"{k}: {json.dumps(str(v), ensure_ascii=False)}")
    out += ["---", "", f"# {c['title']}", ""]
    if c["provenance"]:
        out += [f"_{c['provenance']}_", ""]
    out += ["## Questions & answers", ""]
    if c["questions"]:
        out += ["| Question | Chosen | Notes |", "|---|---|---|"]
        for q in c["questions"]:
            out.append(f"| {md_escape(q['title'])} | {md_escape(q['chosen_label'] or '—')} | {md_escape(q['notes']) or ''} |")
    else:
        out.append("_No structured questions found in canvas._")
    if c["general_notes"]:
        out += ["", "**General notes from user:** " + md_escape(c["general_notes"])]
    out += ["", "## Resolution", ""]
    r = c["resolution"]
    if r:
        out.append(f"**{r.get('title')}** — {r.get('description', '')}".rstrip(" —"))
        if r.get("summary"):
            out += ["", r["summary"]]
        if r.get("rows"):
            out += ["", "| Question | Decision | Outcome |", "|---|---|---|"]
            for row in r["rows"]:
                out.append(f"| {md_escape(row.get('question',''))} | {md_escape(row.get('decision',''))} | {md_escape(row.get('outcome',''))} |")
    else:
        out.append("_Unresolved — no Resolution card in the canvas yet._")
    out += ["", "---", f"Open in atrium: `atrium note open {c['id']}`", ""]
    return "\n".join(out)


def vault_filename(c: dict, full_id: bool = False) -> str:
    """<date>-<topic-slug>-<id8>.md — the id suffix keeps same-day, same-topic canvases distinct."""
    # every component is reduced to [a-z0-9-] so metadata can never carry path separators or `..`
    date = re.sub(r"[^0-9-]", "", c["date"] or "")[:10] or "0000-00-00"
    ident = re.sub(r"[^a-z0-9]", "", c["id"].lower()) or "noid"
    if not full_id:
        ident = ident[:8]
    return f"{date}-{slugify(c['topic'])}-{ident}.md"


def stored_note_id(path: Path) -> str | None:
    """Read `atrium_note_id` from an exported ADR's frontmatter (None if unreadable)."""
    try:
        fences = 0
        with path.open() as f:
            for line in f:
                if line.strip() == "---":
                    fences += 1
                    if fences == 2:
                        break
                    continue
                if line.startswith("atrium_note_id:"):
                    return json.loads(line.split(":", 1)[1].strip())
    except (OSError, ValueError):
        return None
    return None


def assign_vault_filenames(canvases: list[dict]) -> None:
    """Set c['vault_file'] for every canvas; short-id names that collide (UUIDv7 prefixes bucket
    by ~18 min) fall back to the full id so the mapping is injective."""
    short = collections.Counter(vault_filename(c) for c in canvases)
    for c in canvases:
        name = vault_filename(c)
        c["vault_file"] = vault_filename(c, full_id=True) if short[name] > 1 else name
    dupes = [n for n, k in collections.Counter(c["vault_file"] for c in canvases).items() if k > 1]
    if dupes:
        die(f"vault filename collision even with full ids (duplicate note ids?): {dupes}")


def export_vault(canvases: list[dict], vault_dir: Path, workspace: str, today: str) -> dict:
    dec = vault_dir / "decisions"
    dec.mkdir(parents=True, exist_ok=True)
    written, unchanged = [], []
    assign_vault_filenames(canvases)
    for c in canvases:
        fname = c["vault_file"]
        p = dec / fname
        if p.exists() and stored_note_id(p) != c["id"]:
            # an older (archived) canvas or a hand-written file owns this name — never overwrite it
            fname = c["vault_file"] = vault_filename(c, full_id=True)
            p = dec / fname
        body = render_adr(c, workspace)
        if p.exists() and hashlib.sha256(p.read_bytes()).hexdigest() == hashlib.sha256(body.encode()).hexdigest():
            unchanged.append(fname)
        else:
            p.write_text(body)
            written.append(fname)
    idx = [
        "---", "description: Index of exported atrium decision canvases", "tags:", "  - index", "  - decision-canvas", "---", "",
        "# Decision canvases", "", f"Exported {today} from atrium workspace `{workspace}` by decision-canvas/scripts/decision_index.py.", "",
        "| Date | Topic | Status | Trackers | Record |", "|---|---|---|---|---|",
    ]
    for c in canvases:  # same collection that was exported above (includes misfiled)
        idx.append(f"| {c['date']} | {md_escape(c['topic'])} | {c['status']} | {md_escape(', '.join(c['trackers']) or '—')} | [[decisions/{c['vault_file'][:-3]}]] |")
    (dec / "_index.md").write_text("\n".join(idx) + "\n")
    return {"dir": str(dec), "written": written, "unchanged": unchanged}


# `atrium note` uses canvases for monitors and background logs too. Those never
# posed a question, so asking an agent to "patch Resolution (or resolve as
# 'abandoned')" on one asks it to invent an outcome (#434). Leading \W* clears
# the 👀 / 🔁 status emoji these panes carry.
BACKGROUND_TITLE_RE = re.compile(r"\b(watch|watches|watcher|watching|monitor|monitors|monitoring|background|release loop)\b", re.I)
# The workspace pane taxonomy (CLAUDE.md "Flagging Background Work"): 🔁 loop,
# 👀 monitor, ⏳ blocked-on-external, 🎯 goal. A note titled with one is a
# flagged background pane by convention, whatever else the title says.
BACKGROUND_EMOJI = ("🔁", "👀", "⏳", "🎯")


def is_background_work(c: dict) -> bool:
    """Question evidence outranks every title signal: a canvas that poses a
    question is a decision however its pane was labelled, so `👀 Decide the
    launch date` stays `stale-open`. Only where nothing is being asked do the
    title and the structural rule apply — and "no questions" is structural
    evidence solely when a canvas exists to read, since an html-only note has
    none either and that means unreadable, not undecided."""
    if c.get("questions"):
        return False
    title = (c.get("title") or "").strip()
    if title.startswith(BACKGROUND_EMOJI) or BACKGROUND_TITLE_RE.search(title):
        return True
    return bool(c.get("has_canvas"))


def sweep_tiers(canvases: list[dict], misfiled: list[dict], stale_days: int, archive_days: int, vault_dir: Path | None, now: dt.datetime) -> list[dict]:
    tiers = []
    # Same title and date, different id — a re-run of the canvas builder. Reporting
    # both as stale-open doubles the backlog and invites two conflicting Resolutions.
    # The keeper is chosen here rather than inherited from the caller's sort order,
    # so a differently-ordered `canvases` cannot nominate a different one.
    groups: dict[tuple, list[dict]] = collections.defaultdict(list)
    for c in canvases:
        groups[(c["title"], c["date"])].append(c)
    duplicates: dict[str, str] = {}
    for group in groups.values():
        if len(group) < 2:
            continue
        keep = max(group, key=lambda c: (c.get("date") or "", c.get("created") or "", c["id"]))
        for c in group:
            if c["id"] != keep["id"]:
                duplicates[c["id"]] = keep["id"]
    for c in misfiled:
        tiers.append({"tier": "misfiled", "id": c["id"], "title": c["title"], "why": "title says Decisions: but note is not in decisions/ folder", "action": "move dir under decisions/ (ask)"})
    for c in canvases:
        updated = parse_iso(c["updated"]) or parse_iso(c["created"])
        age = (now - updated).days if updated else None
        if c["status"] != "resolved" and age is not None and age >= stale_days:
            common = {"id": c["id"], "title": c["title"]}
            if c["id"] in duplicates:
                tiers.append({"tier": "duplicate", **common, "why": f"same title and date as {duplicates[c['id']][:8]}", "action": "keep one, delete the other (ask)"})
            elif is_background_work(c):
                why = "background/watch pane" if not c.get("has_canvas") else ("no question elements" if not c.get("questions") else "watch/monitor title")
                tiers.append({"tier": "background-work", **common, "why": f"{why}, untouched {age}d", "action": "reclassify — no decision here to resolve"})
            elif not c.get("has_canvas"):
                # An html-only note. The loader sees no elements, so "no questions"
                # here means "unreadable", not "not a decision" — 019f96b3 is a
                # genuine sign-off that predates the canvas format.
                tiers.append({"tier": "not-a-canvas", **common, "why": f"no note.canvas.json, untouched {age}d", "action": "read the note by hand — sweep cannot see questions or Resolution"})
            else:
                tiers.append({"tier": "stale-open", **common, "why": f"{c['status']}, untouched {age}d", "action": "patch Resolution (or resolve as 'abandoned') — ask"})
        exported = bool(vault_dir and c.get("vault_file") and (vault_dir / "decisions" / c["vault_file"]).exists())
        if vault_dir and not exported:
            tiers.append({"tier": "unexported", "id": c["id"], "title": c["title"], "why": "no vault record", "action": "run --export-vault"})
        if c["status"] == "resolved" and exported:
            # Resolution time: the canvas-patch that adds the Resolution card bumps updatedAt, so
            # updatedAt is an upper bound on when it was resolved. If the card also carries a
            # "(YYYY-MM-DD)" date, take the later of the two; if neither exists, never archive.
            res_dt = parse_iso(c["updated"])
            r = c["resolution"] or {}
            m = re.search(r"(\d{4}-\d{2}-\d{2})", f"{r.get('title','')} {r.get('description','')}")
            if m:
                card_dt = dt.datetime.fromisoformat(m.group(1)).replace(tzinfo=dt.timezone.utc)
                res_dt = max(res_dt, card_dt) if res_dt else card_dt
            if res_dt is not None:
                res_age = (now - res_dt).days
                if res_age >= archive_days:
                    tiers.append({"tier": "archivable", "id": c["id"], "title": c["title"], "why": f"resolved {res_age}d ago, vault copy exists", "action": "atrium note delete <id> --confirm — ask"})
    return tiers


def write_note_body(nid: str, md: str) -> None:
    """`note write` accepts --content/--from-file/stdin; a temp file sidesteps argv limits and stdin ambiguity."""
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as f:
        f.write(md)
        tmp = f.name
    try:
        atrium("note", "write", nid, "--from-file", tmp)
    finally:
        Path(tmp).unlink(missing_ok=True)


def upsert_index_note(md: str) -> str:
    listing = json.loads(atrium("note", "list", "--folder", "decisions", "--json") or "[]")
    items = listing if isinstance(listing, list) else listing.get("notes") or listing.get("items") or []
    existing = next((n for n in items if n.get("title") == INDEX_TITLE), None)
    if existing:
        nid = existing.get("id") or existing.get("noteId")
        write_note_body(nid, md)  # --source override unsupported on write; meta.source stays agent
        return nid
    out = atrium("note", "new", "--type", "markdown", "--title", INDEX_TITLE, "--folder", "decisions", "--tags", "decision,index", "--source", "agent", "--json")
    j = json.loads(out)
    nid = (j.get("meta") or {}).get("id") or j.get("id")
    if not nid:  # `note new --json` can return null fields; recover the id by title
        listing = json.loads(atrium("note", "list", "--folder", "decisions", "--json") or "[]")
        items = listing if isinstance(listing, list) else listing.get("notes") or listing.get("items") or []
        nid = next((n.get("id") or n.get("noteId") for n in items if n.get("title") == INDEX_TITLE), None)
    if not nid:
        die(f"created '{INDEX_TITLE}' but could not determine its id")
    write_note_body(nid, md)
    return nid


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--notes-root", default=os.path.join(os.environ.get("ATRIUM_DATA_DIR", os.path.expanduser("~/.atrium")), "notes"))
    ap.add_argument("--workspace", help="atrium workspace id (default: ATRIUM_WORKSPACE_ID or `atrium context`)")
    ap.add_argument("--index-out", help="write markdown index to FILE ('-' = stdout)")
    ap.add_argument("--upsert-note", action="store_true", help=f"create/update the '{INDEX_TITLE}' note in atrium")
    ap.add_argument("--export-vault", metavar="DIR", help="export ADR markdown per canvas under DIR/decisions/")
    ap.add_argument("--sweep-report", action="store_true", help="print lifecycle tiers for atrium-workspace-sweep")
    ap.add_argument("--stale-days", type=int, default=30)
    ap.add_argument("--archive-days", type=int, default=90)
    ap.add_argument("--json", action="store_true", help="dump scan as JSON to stdout")
    a = ap.parse_args()

    workspace = resolve_workspace(a.workspace)
    canvases, misfiled = scan(Path(a.notes_root), workspace)
    now = dt.datetime.now(dt.timezone.utc)
    today = now.date().isoformat()
    vault_dir = Path(os.path.expanduser(a.export_vault)) if a.export_vault else None

    export_result = export_vault(canvases + misfiled, vault_dir, workspace, today) if vault_dir else None  # misfiled ones are still decisions
    index_md = render_index(canvases, misfiled, today, vault_dir)

    nothing_asked = not (a.index_out or a.upsert_note or a.export_vault or a.sweep_report or a.json)
    if a.index_out == "-" or nothing_asked:
        sys.stdout.write(index_md)
    elif a.index_out:
        Path(a.index_out).write_text(index_md)
        print(f"index → {a.index_out}", file=sys.stderr)
    if a.upsert_note:
        nid = upsert_index_note(index_md)
        print(f"index note upserted: {nid}", file=sys.stderr)
    if export_result:
        print(f"vault export → {export_result['dir']}: {len(export_result['written'])} written, {len(export_result['unchanged'])} unchanged", file=sys.stderr)
    tiers = None
    if a.sweep_report:
        tiers = sweep_tiers(canvases, misfiled, a.stale_days, a.archive_days, vault_dir, now)
        out = sys.stderr if a.json else sys.stdout  # keep stdout pure JSON when --json is combined
        if not tiers:
            print("decision canvases: nothing to sweep", file=out)
        else:
            print("tier\tid\ttitle\twhy\taction", file=out)
            for t in tiers:
                print(f"{t['tier']}\t{t['id'][:8]}\t{t['title']}\t{t['why']}\t{t['action']}", file=out)
    if a.json:
        json.dump({"workspace": workspace, "canvases": canvases, "misfiled": misfiled, "export": export_result, "sweep": tiers}, sys.stdout, indent=1, default=str)
        print()


if __name__ == "__main__":
    main()
