#!/usr/bin/env python3
"""Build atrium canvas skeleton + JSONL patches from a decision-canvas manifest.

Usage:
    build_question_patches.py manifest.json \
        --skeleton-out spec.json --patches-out patches.jsonl [--repo /path/to/repo]

Then:
    NOTE_ID=$(atrium note new --type canvas --title "..." --open --source agent \
        --send-framing "Decisions:\\n\\n{payload}" --spec spec.json --json | jq -r '.meta.id // .id')
    atrium note canvas-patch "$NOTE_ID" < patches.jsonl

Manifest schema: see SKILL.md. Code snippets are read from real files at build
time; a missing file or out-of-range line window is a hard error (never ship
stale evidence).
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.parse
from pathlib import Path

MAX_IMAGE_BYTES = 300_000  # ~200KB of PNG once base64-encoded


def die(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(1)


class Builder:
    def __init__(self, repo: Path):
        self.repo = repo
        self.ops: list[dict] = []
        self._n = 0

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


def build(manifest: dict, repo: Path) -> tuple[dict, list[dict]]:
    b = Builder(repo)
    questions = manifest.get("questions") or die("manifest has no questions")
    seen_ids: set[str] = set()

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

    for q in questions:
        qid = q.get("id") or die("question missing id")
        if qid in seen_ids:
            die(f"duplicate question id: {qid}")
        seen_ids.add(qid)
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
            skeleton_state[qid] = recommended

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
            skeleton_state[cb["id"]] = bool(cb.get("default", False))

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
        skeleton_state[f"{qid}_notes"] = ""

        b.el(
            card_key,
            {
                "type": "Card",
                "props": {"title": q.get("title", qid), "description": q.get("description", "")},
                "children": children,
            },
        )
        b.child_of("rootStack", card_key)

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


def build_resolution(resolution: dict) -> list[dict]:
    """Ops appending a Resolution card to an already-answered canvas (close the loop).

    resolution = {
        "title": "✅ RESOLVED — <topic> (YYYY-MM-DD)",  # optional; defaults to "Resolution"
        "description": "one-line framing",              # optional; defaults to "date"
        "date": "YYYY-MM-DD",                           # optional; description fallback
        "summary": "...",                               # optional narrative paragraph
        "items": [{"question": "...", "decision": "...",
                   "outcome": "bd-xyz created / commit abc123 / verified clean"}],
    }
    All element keys are fixed and prefixed `resolution*` so they never collide with
    the question phase's counter-based keys (txt_N/code_N/…) when patched into the
    live canvas.
    """
    b = Builder(Path.cwd())
    rows = [
        {
            "question": i.get("question", ""),
            "decision": i.get("decision", ""),
            "outcome": i.get("outcome", ""),
        }
        for i in resolution.get("items", [])
    ]
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
    b.child_of("rootStack", "resolutionCard")
    return b.ops


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("manifest", type=Path)
    ap.add_argument("--repo", type=Path, default=Path.cwd(), help="base for grounding file paths")
    ap.add_argument("--skeleton-out", type=Path)
    ap.add_argument("--patches-out", type=Path, required=True)
    ap.add_argument(
        "--resolution",
        action="store_true",
        help="manifest is a resolution object; emit only ops appending a Resolution card",
    )
    args = ap.parse_args()

    manifest = json.loads(args.manifest.read_text())
    if args.resolution:
        ops = build_resolution(manifest)
        args.patches_out.write_text("\n".join(json.dumps(op) for op in ops) + "\n")
        print(f"{len(ops)} resolution ops -> {args.patches_out}", file=sys.stderr)
        return
    if args.skeleton_out is None:
        die("--skeleton-out is required unless --resolution")
    skeleton, ops = build(manifest, args.repo.resolve())
    args.skeleton_out.write_text(json.dumps(skeleton, indent=2) + "\n")
    args.patches_out.write_text("\n".join(json.dumps(op) for op in ops) + "\n")
    print(
        f"skeleton -> {args.skeleton_out} | {len(ops)} patch ops -> {args.patches_out}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
