#!/usr/bin/env python3
"""Build atrium canvas skeleton + JSONL patches from a decision-canvas manifest.

Usage:
    build_question_patches.py manifest.json [--tabs] \
        --skeleton-out spec.json --patches-out patches.jsonl [--repo /path/to/repo]

--tabs nests the question cards in a Tabs element, one tab per question plus a
Resolution tab. Global notes and the Send button stay below the tabs.

Then:
    NOTE_ID=$(atrium note new --type canvas --title "..." --open --source agent \
        --send-framing "Decisions:\\n\\n{payload}" --spec spec.json --json | jq -r '.meta.id // .id')
    atrium note canvas-patch "$NOTE_ID" < patches.jsonl

Close the loop once the reply is acted on:
    atrium note read "$NOTE_ID" > canvas.json
    build_question_patches.py resolution.json --resolution --canvas canvas.json \
        --patches-out resolution.jsonl
    atrium note canvas-patch "$NOTE_ID" < resolution.jsonl

Add questions to a canvas that is already open (no skeleton; keys never collide):
    atrium note read "$NOTE_ID" > canvas.json
    build_question_patches.py more.json --append --canvas canvas.json --patches-out more.jsonl
    atrium note canvas-patch "$NOTE_ID" < more.jsonl

Manifest schema: see SKILL.md. Code snippets are read from real files at build
time; a missing file or out-of-range line window is a hard error (never ship
stale evidence).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.parse
from pathlib import Path

MAX_IMAGE_BYTES = 300_000  # ~200KB of PNG once base64-encoded
TABS_KEY = "questionTabs"
RESOLUTION_TAB = "resolution"
# Holds the Resolution tab until the reply. Not `resolution*`: decision_index
# reads any element with that prefix as a Resolution, so the canvas would index
# as resolved before anyone answered.
PENDING_KEY = "awaitingResolution"


def die(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(1)


class Builder:
    def __init__(self, repo: Path, start: int = 0):
        self.repo = repo
        self.ops: list[dict] = []
        self._n = start

    def key(self, prefix: str) -> str:
        self._n += 1
        return f"{prefix}_{self._n}"

    def el(self, key: str, element: dict) -> str:
        self.ops.append({"op": "add", "path": f"/elements/{key}", "value": element})
        return key

    def child_of(self, parent: str, key: str) -> None:
        self.ops.append({"op": "add", "path": f"/elements/{parent}/children/-", "value": key})

    def state(self, pointer: str, value) -> None:
        self.ops.append({"op": "add", "path": f"/state/{pointer}", "value": value})

    # --- grounding item renderers -------------------------------------------

    def text(self, content: str, tone: str = "muted") -> str:
        return self.el(
            self.key("txt"),
            {"type": "Text", "props": {"content": content, "tone": tone}, "children": []},
        )

    def _resolve_in_repo(self, rel: str) -> Path:
        # Manifest paths may come from an autonomous agent — confine to repo.
        path = (self.repo / rel).resolve()
        try:
            path.relative_to(self.repo.resolve())
        except ValueError:
            die(f"grounding file escapes repo: {rel}")
        return path

    def code_snippet(self, rel: str, start: int, end: int) -> str:
        path = self._resolve_in_repo(rel)
        if not path.is_file():
            die(f"grounding file not found: {path}")
        lines = path.read_text(errors="replace").splitlines()
        if start < 1 or end > len(lines) or start > end:
            die(f"line window {start}-{end} out of range for {rel} ({len(lines)} lines)")
        return self.el(
            self.key("code"),
            {
                "type": "Code",
                "props": {
                    "code": "\n".join(lines[start - 1 : end]),
                    "filePath": str(path),
                    "startLine": start,
                },
                "children": [],
            },
        )

    def code_literal(self, code: str, language: str = "sql") -> str:
        return self.el(
            self.key("code"),
            {"type": "Code", "props": {"code": code, "language": language}, "children": []},
        )

    def open_button(self, rel: str) -> str:
        path = self._resolve_in_repo(rel)
        uri = "atrium://commands/file.open?path=" + urllib.parse.quote(str(path), safe="")
        return self.el(
            self.key("open"),
            {
                "type": "Button",
                "props": {"label": f"Open {rel}", "variant": "link"},
                "children": [],
                "on": {"press": {"action": "atrium_command", "params": {"uri": uri}}},
            },
        )

    def chart(self, item: dict) -> list[str]:
        kind = item.get("kind", "bar")
        comp = {"bar": "BarGraph", "line": "LineGraph"}.get(kind)
        if comp is None:
            die(f"chart kind must be bar|line, got {kind!r}")
        data = item.get("data")
        if not isinstance(data, list) or not data:
            die("chart grounding needs a non-empty 'data' array of {name, ...series} rows")
        keys = [
            self.el(
                self.key("chart"),
                {
                    "type": comp,
                    "props": {"title": item.get("title", ""), "data": data},
                    "children": [],
                },
            )
        ]
        if item.get("query"):
            keys.append(self.code_literal(item["query"], item.get("query_language", "sql")))
        if item.get("provenance"):
            keys.append(self.text(f"Source: {item['provenance']}"))
        return keys

    def image(self, item: dict) -> list[str]:
        src = item.get("src", "")
        if not src.startswith("data:"):
            die("image grounding requires a data: URI src (canvas panes may not reach file paths)")
        if len(src) > MAX_IMAGE_BYTES:
            die(f"image data URI is {len(src)} bytes (> {MAX_IMAGE_BYTES}); downsample it")
        keys = [
            self.el(
                self.key("img"),
                {"type": "Image", "props": {"src": src, "alt": item.get("alt", "")}, "children": []},
            )
        ]
        if item.get("provenance"):
            keys.append(self.text(f"Source: {item['provenance']}"))
        return keys

    def grounding_items(self, items: list[dict]) -> list[str]:
        keys: list[str] = []
        for item in items:
            t = item.get("type")
            if t == "text":
                keys.append(self.text(item["content"]))
            elif t == "code":
                keys.append(self.code_snippet(item["file"], item["start"], item["end"]))
            elif t == "open":
                keys.append(self.open_button(item["file"]))
            elif t == "chart":
                keys.extend(self.chart(item))
            elif t == "image":
                keys.extend(self.image(item))
            else:
                die(f"unknown grounding type: {t!r}")
        return keys


def question_card(b: Builder, q: dict, state: dict) -> str:
    """Emit one question's Card (and its children) into b.ops; seed its keys in state.

    Returns the card key. The caller links it into rootStack.
    """
    qid = q["id"]
    card_key = f"{qid}_card"
    children: list[str] = []

    if q.get("context"):
        children.append(b.text(q["context"]))

    options = q.get("options") or die(f"{qid}: no options")
    recommended = q.get("recommended")
    if recommended is not None and recommended not in {o["value"] for o in options}:
        die(f"{qid}: recommended {recommended!r} not among option values")
    children.append(
        b.el(
            f"{qid}_radio",
            {
                "type": "Radio",
                "props": {"value": {"$bindState": f"/{qid}"}, "options": options},
                "children": [],
            },
        )
    )
    if recommended is not None:
        state[qid] = recommended

    if q.get("checkbox"):
        cb = q["checkbox"]
        children.append(
            b.el(
                f"{qid}_checkbox",
                {
                    "type": "Checkbox",
                    "props": {"checked": {"$bindState": f"/{cb['id']}"}, "label": cb["label"]},
                    "children": [],
                },
            )
        )
        state[cb["id"]] = bool(cb.get("default", False))

    if q.get("grounding"):
        gkeys = b.grounding_items(q["grounding"])
        children.append(
            b.el(
                f"{qid}_grounding",
                {
                    "type": "Collapsible",
                    "props": {"title": "Grounding — evidence", "defaultOpen": False},
                    "children": gkeys,
                },
            )
        )

    # Per-question notes — ALWAYS present so the user can qualify a single
    # decision inline ("yes but only for prod", "recommended is wrong because…").
    # Unique key {qid}_notes joins the reply schema; distinct from the global /notes.
    children.append(
        b.el(
            f"{qid}_notesInput",
            {
                "type": "Textarea",
                "props": {
                    "value": {"$bindState": f"/{qid}_notes"},
                    "placeholder": q.get("notes_placeholder", "Notes / override for this decision (optional)…"),
                    "rows": 2,
                },
                "children": [],
            },
        )
    )
    state[f"{qid}_notes"] = ""

    b.el(
        card_key,
        {
            "type": "Card",
            "props": {"title": q.get("title", qid), "description": q.get("description", "")},
            "children": children,
        },
    )
    return card_key


def tab_label(qid: str, n: int) -> str:
    """`q3_ci_cache` -> `3 ci cache`. A tab strip has room for a word or two."""
    m = re.match(r"q(\d+)_(.+)", qid)
    return f"{m[1]} {m[2].replace('_', ' ')}" if m else f"{n} {qid}"


def build(manifest: dict, repo: Path, tabs: bool = False) -> tuple[dict, list[dict]]:
    b = Builder(repo)
    questions = manifest.get("questions") or die("manifest has no questions")
    seen_ids: set[str] = set()
    tab_list: list[dict] = []

    skeleton_state: dict = {"notes": ""}
    skeleton = {
        "root": "rootStack",
        "elements": {
            "rootStack": {
                "type": "Stack",
                "props": {"direction": "column", "gap": 16, "padding": 16},
                "children": ["header"] + (["intro"] if manifest.get("intro") else []),
            },
            "header": {
                "type": "Heading",
                "props": {"text": manifest.get("title", "Decisions"), "level": 2},
                "children": [],
            },
        },
        "state": skeleton_state,
    }
    if manifest.get("intro"):
        skeleton["elements"]["intro"] = {
            "type": "Text",
            "props": {"content": manifest["intro"], "tone": "muted"},
            "children": [],
        }

    for n, q in enumerate(questions, 1):
        qid = q.get("id") or die("question missing id")
        if qid in seen_ids:
            die(f"duplicate question id: {qid}")
        if tabs and qid == RESOLUTION_TAB:
            die(f"question id {qid!r} is reserved for the Resolution tab")
        seen_ids.add(qid)
        card_key = question_card(b, q, skeleton_state)
        if tabs:
            tab_list.append({"value": qid, "label": q.get("tab") or tab_label(qid, n)})
        else:
            b.child_of("rootStack", card_key)

    if tabs:
        # Added after the cards so no op ever references an element not yet added.
        b.el(
            PENDING_KEY,
            {
                "type": "Text",
                "props": {"content": "Filled in after you send: each decision and what was done.", "tone": "muted"},
                "children": [],
            },
        )
        # defaultValue, not a bound value: a bound tab position would land in the reply payload.
        b.el(
            TABS_KEY,
            {
                "type": "Tabs",
                "props": {
                    "tabs": tab_list + [{"value": RESOLUTION_TAB, "label": "Resolution"}],
                    "defaultValue": tab_list[0]["value"],
                },
                "children": [f"{t['value']}_card" for t in tab_list] + [PENDING_KEY],
            },
        )
        b.child_of("rootStack", TABS_KEY)

    # Notes + submit
    notes_key = b.el(
        "notesCard",
        {
            "type": "Card",
            "props": {"title": "Anything else"},
            "children": [
                b.el(
                    "notesInput",
                    {
                        "type": "Textarea",
                        "props": {
                            "value": {"$bindState": "/notes"},
                            "placeholder": manifest.get(
                                "notes_placeholder", "Overrides, constraints, corrections…"
                            ),
                            "rows": 4,
                        },
                        "children": [],
                    },
                )
            ],
        },
    )
    b.child_of("rootStack", notes_key)
    submit_key = b.el(
        "submitBtn",
        {
            "type": "Button",
            "props": {"label": "Send decisions to agent", "variant": "primary"},
            "children": [],
            "on": {"press": {"action": "send_to_agent", "params": {"payload": {"$state": ""}}}},
        },
    )
    row = b.el(
        "submitRow",
        {
            "type": "Stack",
            "props": {"direction": "row", "gap": 12, "justify": "end"},
            "children": [submit_key],
        },
    )
    b.child_of("rootStack", row)

    if manifest.get("provenance"):
        prov = b.el(
            "provenanceFooter",
            {
                "type": "Text",
                "props": {"content": manifest["provenance"], "tone": "muted"},
                "children": [],
            },
        )
        b.child_of("rootStack", prov)

    return skeleton, b.ops


def resolution_tab(elements: dict) -> tuple[str, int] | None:
    """(Tabs id, panel index) of the tab a tabbed canvas keeps for the Resolution.

    Matches the --tabs placeholder, a Resolution already in the tab, and the
    `resolution*` panel that hand-written op rewrites used before --tabs existed.
    """
    for eid, el in elements.items():
        if el.get("type") != "Tabs":
            continue
        for i, child in enumerate(el.get("children") or []):
            if child == PENDING_KEY or str(child).startswith("resolution"):
                return eid, i
    return None


def build_append(manifest: dict, canvas: dict, repo: Path) -> list[dict]:
    """Ops adding the manifest's question cards to a live canvas, before its notesCard.
    On a --tabs canvas each card becomes a tab, ahead of the Resolution tab.

    Only `questions` is read; the live canvas already has its header, notes and
    submit shell. Counter keys (txt_N/code_N/…) start past the canvas's highest N,
    and any op that would overwrite an existing element or state key is a hard
    error — `add` silently replaces, and the user may have answered already.
    """
    elements = canvas.get("elements") or die("live canvas has no elements")
    state = canvas.get("state") or {}
    root = canvas.get("root", "rootStack")
    slot = resolution_tab(elements)
    if slot:
        parent, at = slot
    else:
        parent = root
        root_children = elements.get(root, {}).get("children", [])
        anchor = next((k for k in ("notesCard", "submitRow") if k in root_children), None)
        if anchor is None:
            die(f"live canvas {root} has no notesCard or submitRow to insert before")
        at = root_children.index(anchor)

    last_n = max(
        (int(m.group(1)) for k in elements if (m := re.fullmatch(r"(?:txt|code|open|chart|img)_(\d+)", k))),
        default=0,
    )
    b = Builder(repo, start=last_n)
    questions = manifest.get("questions") or die("manifest has no questions")
    new_state: dict = {}
    card_keys: list[str] = []
    tabs: list[dict] = []
    for q in questions:
        qid = q.get("id") or die("question missing id")
        if f"{qid}_card" in elements or qid in state or f"{qid}_card" in card_keys:
            die(f"question id {qid} already on the canvas or in the manifest")
        if slot and qid == RESOLUTION_TAB:
            die(f"question id {qid!r} is reserved for the Resolution tab")
        card_keys.append(question_card(b, q, new_state))
        tabs.append({"value": qid, "label": q.get("tab") or tab_label(qid, at + len(tabs) + 1)})

    added = {op["path"].split("/")[2] for op in b.ops if op["path"].count("/") == 2}
    clashes = sorted((added & set(elements)) | (set(new_state) & set(state)))
    if clashes:
        die(f"append would overwrite live keys: {', '.join(clashes)}")

    links = [
        {"op": "add", "path": f"/elements/{parent}/children/{at + i}", "value": key}
        for i, key in enumerate(card_keys)
    ]
    if slot:  # Tabs pairs tabs[i] with children[i]
        links += [
            {"op": "add", "path": f"/elements/{parent}/props/tabs/{at + i}", "value": tab}
            for i, tab in enumerate(tabs)
        ]
    # State first, so each radio renders with its recommendation pre-selected.
    seeds = [{"op": "add", "path": f"/state/{k}", "value": v} for k, v in new_state.items()]
    return seeds + b.ops + links


RESOLVED_SUBMIT_LABEL = "Already resolved (see top) — re-send only to amend"


def option_labels(elements: dict) -> dict[str, dict]:
    """{qid: {option value: option label}} from each question's Radio."""
    out = {}
    for eid, el in elements.items():
        if eid.endswith("_radio") and el.get("type") == "Radio":
            options = (el.get("props") or {}).get("options") or []
            out[eid[: -len("_radio")]] = {
                o.get("value"): o.get("label") for o in options if isinstance(o, dict)
            }
    return out


def decision_label(decision: str, qid: str | None, labels: dict[str, dict]) -> str:
    """Swap a raw option value (`close_all`) for the label the user clicked.

    Without a qid, swap only when the value names one label across every Radio.
    """
    if qid in labels:
        return labels[qid].get(decision) or decision
    hits = {opts[decision] for opts in labels.values() if opts.get(decision)}
    return hits.pop() if len(hits) == 1 else decision


def build_resolution(resolution: dict, canvas: dict) -> list[dict]:
    """Ops that close the loop on an answered canvas.

    resolution = {
        "title": "✅ RESOLVED — <topic> (YYYY-MM-DD)",  # optional; defaults to "Resolution"
        "description": "one-line framing",              # optional; defaults to "date"
        "date": "YYYY-MM-DD",                           # optional; description fallback
        "summary": "...",                               # optional narrative paragraph
        "items": [{"qid": "q1_fixture",                 # optional; fills question, maps decision
                   "question": "...", "decision": "...",
                   "outcome": "bd-xyz created / commit abc123 / verified clean"}],
    }
    `canvas` is the live canvas (`atrium note read <id>`). The card goes directly
    under the heading and intro. Appended last, it sat below every question card,
    the submit button and the provenance footer, so a resolved canvas opened
    looking like an open one (257 of 284 canvases, measured 2026-10-13). On a
    --tabs canvas the card fills the Resolution tab instead, and the tabs open on
    it. The heading gains a ✅ and the submit button stops asking for a send.

    All element keys are fixed and prefixed `resolution*` so they never collide with
    the question phase's counter-based keys (txt_N/code_N/…). Re-running replaces
    the card and moves its single root reference; it never adds a second card.
    """
    elements = canvas.get("elements") or die("canvas has no elements")
    root = canvas.get("root") or die("canvas has no root")
    top = list((elements.get(root) or {}).get("children") or [])
    labels = option_labels(elements)
    b = Builder(Path.cwd())
    rows = []
    for i in resolution.get("items", []):
        qid = i.get("qid")
        card_title = ((elements.get(f"{qid}_card") or {}).get("props") or {}).get("title", "")
        rows.append(
            {
                "question": i.get("question") or card_title or qid or "",
                "decision": decision_label(i.get("decision", ""), qid, labels),
                "outcome": i.get("outcome", ""),
            }
        )
    children = []
    if resolution.get("summary"):
        # Fixed key (NOT b.text()'s txt_N counter): build_resolution runs against an
        # already-materialized canvas, and a counter-based txt_1 would collide with the
        # first question's grounding text element and silently replace it.
        children.append(
            b.el(
                "resolutionSummary",
                {
                    "type": "Text",
                    "props": {"content": resolution["summary"], "tone": "muted"},
                    "children": [],
                },
            )
        )
    if rows:
        children.append(
            b.el(
                "resolutionTable",
                {
                    "type": "Table",
                    "props": {
                        "columns": [
                            {"key": "question", "label": "Question"},
                            {"key": "decision", "label": "Decision"},
                            {"key": "outcome", "label": "Outcome"},
                        ],
                        "rows": rows,
                    },
                    "children": [],
                },
            )
        )
    b.el(
        "resolutionCard",
        {
            "type": "Card",
            "props": {
                "title": resolution.get("title", "Resolution"),
                "description": resolution.get("description", resolution.get("date", "")),
            },
            "children": children,
        },
    )
    # Old re-runs appended a second reference; drop every one, last first so
    # earlier indexes stay valid.
    for idx in reversed([i for i, eid in enumerate(top) if eid == "resolutionCard"]):
        b.ops.append({"op": "remove", "path": f"/elements/{root}/children/{idx}"})
        del top[idx]
    slot = resolution_tab(elements)
    if slot:
        tabs_id, idx = slot
        tabs_el = elements[tabs_id]
        old = tabs_el["children"][idx]
        b.ops.append({"op": "replace", "path": f"/elements/{tabs_id}/children/{idx}", "value": "resolutionCard"})
        if old != "resolutionCard":
            b.ops.append({"op": "remove", "path": f"/elements/{old}"})
        props = dict(tabs_el.get("props") or {})
        tab_list = [dict(t) for t in props.get("tabs") or []]
        if idx < len(tab_list):
            label = tab_list[idx].get("label") or "Resolution"
            tab_list[idx]["label"] = label if label.startswith("✅") else f"✅ {label}"
            # Open on the Resolution, as the flat layout puts it at the top.
            props.update(tabs=tab_list, defaultValue=tab_list[idx].get("value"))
            b.ops.append({"op": "replace", "path": f"/elements/{tabs_id}/props", "value": props})
    else:
        # Skip the heading and intro Text that open the canvas.
        pos = 0
        while pos < len(top) and (elements.get(top[pos]) or {}).get("type") in ("Heading", "Text"):
            pos += 1
        b.ops.append({"op": "add", "path": f"/elements/{root}/children/{pos}", "value": "resolutionCard"})

    heading = next((e for e in top if (elements.get(e) or {}).get("type") == "Heading"), None)
    text = ((elements.get(heading) or {}).get("props") or {}).get("text", "")
    if heading and not text.startswith("✅"):
        b.ops.append({"op": "replace", "path": f"/elements/{heading}/props/text", "value": f"✅ {text}"})
    for eid, el in elements.items():
        if el.get("type") == "Button" and ((el.get("on") or {}).get("press") or {}).get("action") == "send_to_agent":
            props = {**(el.get("props") or {}), "label": RESOLVED_SUBMIT_LABEL, "variant": "secondary"}
            b.ops.append({"op": "replace", "path": f"/elements/{eid}/props", "value": props})
    return b.ops


def write_ops(path: Path, ops: list[dict]) -> None:
    path.write_text("\n".join(json.dumps(op) for op in ops) + "\n")


def load_canvas(path: Path | None) -> dict:
    if path is None:
        die('--resolution and --append need --canvas: atrium note read "$NOTE_ID" > canvas.json')
    try:  # a failed `note read` leaves an empty file
        canvas = json.loads(path.read_text())
        if isinstance(canvas.get("content"), str):  # `note read --json` wraps the canvas
            canvas = json.loads(canvas["content"])
    except json.JSONDecodeError as e:
        die(f"--canvas {path} is not canvas JSON ({e}); re-run atrium note read")
    return canvas


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("manifest", type=Path)
    ap.add_argument("--repo", type=Path, default=Path.cwd(), help="base for grounding file paths")
    ap.add_argument("--skeleton-out", type=Path)
    ap.add_argument("--patches-out", type=Path, required=True)
    ap.add_argument(
        "--tabs",
        action="store_true",
        help="one tab per question plus a Resolution tab; --resolution and --append find that tab themselves",
    )
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument(
        "--resolution",
        action="store_true",
        help="manifest is a resolution object; emit only the Resolution card ops",
    )
    mode.add_argument(
        "--append",
        action="store_true",
        help="emit only ops adding the manifest's questions to the live --canvas",
    )
    ap.add_argument(
        "--canvas",
        type=Path,
        help="with --resolution/--append: the live canvas (`atrium note read <id>` output, or note.canvas.json)",
    )
    args = ap.parse_args()

    manifest = json.loads(args.manifest.read_text())
    if args.resolution:
        ops = build_resolution(manifest, load_canvas(args.canvas))
        write_ops(args.patches_out, ops)
        print(f"{len(ops)} resolution ops -> {args.patches_out}", file=sys.stderr)
        return
    if args.append:
        ops = build_append(manifest, load_canvas(args.canvas), args.repo.resolve())
        write_ops(args.patches_out, ops)
        print(f"{len(ops)} append ops -> {args.patches_out}", file=sys.stderr)
        return
    if args.skeleton_out is None:
        die("--skeleton-out is required unless --resolution or --append")
    skeleton, ops = build(manifest, args.repo.resolve(), tabs=args.tabs)
    args.skeleton_out.write_text(json.dumps(skeleton, indent=2) + "\n")
    write_ops(args.patches_out, ops)
    print(
        f"skeleton -> {args.skeleton_out} | {len(ops)} patch ops -> {args.patches_out}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
