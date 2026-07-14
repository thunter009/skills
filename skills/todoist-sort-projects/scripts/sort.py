#!/usr/bin/env python3
"""Sort all Todoist projects alphabetically within each parent, recursive.

Inbox is pinned at position 0. Uses the Todoist sync API's project_reorder
command to do the whole tree in one atomic call.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import uuid
from collections import defaultdict
from pathlib import Path

CONFIG_PATH = Path.home() / ".config" / "todoist-cli" / "config.json"
SYNC_URL = "https://api.todoist.com/api/v1/sync"


def load_token() -> str:
    """Resolve a Todoist API token.

    The official `td` CLI moved to config_version 2, which stores the token in
    the OS keychain instead of as `api_token` in config.json. Resolution order:
    TODOIST_API_TOKEN env var, `td auth token view` (current CLI), then the
    legacy config.json field.
    """
    env = os.environ.get("TODOIST_API_TOKEN")
    if env:
        return env.strip()
    try:
        r = subprocess.run(
            ["td", "auth", "token", "view"],
            capture_output=True, text=True, check=True,
        )
        tok = r.stdout.strip()
        if tok:
            return tok
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    if CONFIG_PATH.exists():
        try:
            return json.loads(CONFIG_PATH.read_text())["api_token"]
        except (json.JSONDecodeError, KeyError):
            pass
    sys.exit("No Todoist API token found. Run `td auth login` or set TODOIST_API_TOKEN.")


def fetch_projects() -> list[dict]:
    r = subprocess.run(
        ["td", "project", "list", "--json", "--full", "--all"],
        capture_output=True, text=True, check=True,
    )
    return json.loads(r.stdout)["results"]


def compute_reorder(projects: list[dict]) -> list[dict]:
    by_parent: dict[str | None, list[dict]] = defaultdict(list)
    for p in projects:
        by_parent[p.get("parentId")].append(p)

    items: list[dict] = []
    for kids in by_parent.values():
        # Inbox stays first; rest sorted case-insensitive by name
        kids_sorted = sorted(
            kids,
            key=lambda x: (not x.get("inboxProject", False), x["name"].lower()),
        )
        for i, p in enumerate(kids_sorted, 1):
            items.append({"id": p["id"], "child_order": i})
    return items


def send_reorder(token: str, items: list[dict]) -> dict:
    cmd = {
        "type": "project_reorder",
        "uuid": str(uuid.uuid4()),
        "args": {"projects": items},
    }
    r = subprocess.run(
        [
            "curl", "-sS", "-X", "POST", SYNC_URL,
            "-H", f"Authorization: Bearer {token}",
            "--data-urlencode", f"commands={json.dumps([cmd])}",
        ],
        capture_output=True, text=True, check=False,
    )
    if r.returncode != 0:
        detail = (r.stderr or r.stdout).strip() or f"curl exited {r.returncode}"
        raise RuntimeError(f"Todoist sync API request failed: {detail}")
    try:
        data = json.loads(r.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Todoist sync API returned non-JSON response: {exc}") from exc
    if not isinstance(data, dict) or "sync_status" not in data:
        raise RuntimeError(f"Todoist sync API response missing sync_status: {json.dumps(data)}")
    return data


def main() -> int:
    token = load_token()
    projects = fetch_projects()
    items = compute_reorder(projects)
    parents = {p.get("parentId") for p in projects}
    print(f"Reordering {len(items)} projects across {len(parents)} parents...")
    try:
        resp = send_reorder(token, items)
    except RuntimeError as exc:
        print(f"FAIL: {exc}")
        return 1
    status = resp.get("sync_status", {})
    failures = {k: v for k, v in status.items() if v != "ok"}
    if failures:
        print("FAIL:", json.dumps(failures, indent=2))
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
