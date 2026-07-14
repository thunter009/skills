---
name: update-session
description: Append a structured session record to the repo history log.
when-to-use:
- update session, log repo session, add history entry
- When recording work in docs/history
user_invocable: true
category: meta
---

# Update session details

You are a diligent project historian. Append a new, well-structured session record to the repository's history system. Create a new file at docs/history/YYYY/MM/YYYY-MM-DD-session-NN.md (NN auto-increments per day), and prepend a link to it in docs/history/index.md under a "Sessions" section, most-recent first. Keep a machine-readable YAML header plus human-friendly sections. Ask for any missing info explicitly.

Environment assumptions:

- History root: docs/history
- File pattern: docs/history/YYYY/MM/YYYY-MM-DD-session-NN.md
- Index file: docs/history/index.md
- Session numbering: start at 01 each day; increment based on existing files for the same date
- Git context available (best effort): author, email, branch, short SHA, remote URL (for optional commit link)

When creating a session file, include:

- YAML header fields:
  - date: YYYY-MM-DD (session date, not necessarily now)
  - timestamp_utc: ISO 8601 (e.g., 2025-10-07T14:03:00Z)
  - author: "Full Name <email>"
  - branch: string or "no-git"
  - commit: short SHA or "no-git"
  - repo: remote URL if available
  - title: short string
  - tags: array of strings
  - scope: array of file paths/symbols
  - session_number: integer (NN)
  - optional: commit_url if repo is GitHub-like
- Body sections:
  - H1: YYYY-MM-DD -- Session NN: {title}
  - Summary
    - Changes: concise bullets or prose
    - Rationale: why
    - Impacts: breaking/perf/security/UX
    - Testing: how validated
  - Follow-ups: bullet list (or "- None"); tag items already filed with `(tracking: <tracker> <id>)` — if the session is ending rather than pausing, resolve them per CLAUDE.md Session Completion rule 7 (followup-dedup, create-by-default) instead of just listing
  - Links: issues/PRs/docs/refs (or "- N/A")

Input (from $ARGUMENTS; may be YAML/JSON/plain text; partial is OK): $ARGUMENTS

Expected behavior:

- Parse $ARGUMENTS. If fields are missing, ask targeted follow-up questions:
  - Required: title, changes, rationale
  - Helpful: scope, tags, impacts, testing, follow_ups, links, date (default to today in repo's timezone if unspecified)
- Determine session path and NN by inspecting existing files under docs/history/YYYY/MM for the specified date.
- Generate the new session file content as Markdown, ready to save at the exact path.
- Produce the precise Markdown line to prepend to docs/history/index.md linking to this new session, keeping most-recent-first under "## Sessions".
- If a remote URL looks like GitHub or GitLab, include commit_url in YAML as repo/commit/{SHA}.
- Escape special characters safely in YAML strings; represent tags/scope as YAML arrays of quoted strings.

Output format:

- Session File Path: docs/history/YYYY/MM/YYYY-MM-DD-session-NN.md
- Session File Content:

    ```markdown
    --- 
    date: "YYYY-MM-DD"
    timestamp_utc: "YYYY-MM-DDTHH:MM:SSZ"
    author: "Full Name <email@example.com>"
    branch: "branch-or-no-git"
    commit: "shortsha-or-no-git"
    repo: "https://host/org/repo"
    commit_url: "https://host/org/repo/commit/shortsha"
    title: "Short title"
    tags: ["tag1", "tag2"]
    scope: ["path/file1", "path/file2"]
    session_number: NN
    ---
    
    # YYYY-MM-DD -- Session NN: Short title
    
    ## Summary
    - Changes: ...
    - Rationale: ...
    - Impacts: ...
    - Testing: ...
    
    ## Follow-ups
    - None
    
    ## Links
    - N/A
    ```

- Index Update:
  - File: docs/history/index.md
  - Section: "## Sessions" (create header if missing)
  - Prepend Line:
    - [YYYY-MM-DD -- Session NN: {title}](YYYY/MM/YYYY-MM-DD-session-NN.md)

Validation checklist before output:

- Path matches date and NN; NN is two digits.
- YAML is valid (strings quoted, arrays bracketed, ISO timestamp Z).
- All required sections present; placeholders avoided. If unknown, ask.
- Links section uses bullet list.
- Follow-ups section uses bullet list; "- None" if empty.

If information is missing, respond with a brief, numbered list of the exact fields needed to proceed, and do not fabricate values.

Example minimal $ARGUMENTS schema (YAML; partial is fine):

```yaml
date: 2025-10-07
title: Fix token refresh race
scope:
  - src/auth/refresh.ts
  - tests/auth/test_refresh.py
tags:
  - auth
  - bugfix
changes: |
  - Debounced parallel refresh calls with single-flight.
  - Added jitter to retry backoff.
rationale: |
  Parallel refreshes caused 401 loops and token clobbering.
impacts: |
  - Potentially fewer auth calls; no breaking API changes.
testing: |
  - Added unit tests; verified in staging with concurrent load.
follow_ups:
  - Monitor 401 rates in Sentry for 72h.
  - Consider lock duration metrics.
links:
  - PR #123
  - Incident INC-456
branch: feature/auth-refresh
commit: a1b2c3d
repo: https://github.com/acme/project
```
