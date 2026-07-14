---
name: codex
description: Run Codex CLI for parallel implementation, review, or second opinions.
when-to-use:
- codex, ask codex, run codex, second opinion
- When you want Codex to inspect or edit in parallel
user_invocable: true
allowed-tools: Bash(codex:*)
category: code
---

# /codex — Run OpenAI Codex from Claude Code

Delegate a task to OpenAI's Codex CLI agent and return results.

## Arguments

```
/codex <prompt>                    # run task, suggest-only (default)
/codex --apply <prompt>            # run task, apply changes to workspace
/codex --review                    # code review of current changes
/codex --model <model> <prompt>    # override model (default: gpt-5.4)
```

## Workflow

### 1. Parse Arguments

Extract from `$ARGUMENTS`:
- `--apply` flag → use `--sandbox workspace-write` (otherwise `--sandbox read-only`)
- `--review` flag → use `codex exec review` subcommand with no `--sandbox` flag
- `--model <model>` → override model (default: `gpt-5.4`)
- Everything else → the prompt

### 2. Run Codex

Execute Codex CLI non-interactively using `codex exec`:

```bash
# Standard task (suggest-only)
codex exec \
  -m "gpt-5.4" \
  --sandbox read-only \
  --skip-git-repo-check \
  --ephemeral \
  "<prompt>"

# With --apply (writes to workspace)
codex exec \
  -m "gpt-5.4" \
  --sandbox workspace-write \
  --skip-git-repo-check \
  --ephemeral \
  "<prompt>"

# Code review
codex exec review \
  -m "gpt-5.4" \
  --ephemeral
```

Key flags:
- `-m gpt-5.4` — default model (user can override with `--model`)
- `--sandbox read-only` — safe default for standard exec runs, no file writes
- `--ephemeral` — don't persist codex session files
- `--skip-git-repo-check` — work outside git repos too

### 3. Capture & Present Output

- Run via Bash tool, capture stdout+stderr
- Set a **5-minute timeout** (300000ms) — Codex tasks can be slow
- If Codex suggests changes (read-only mode), present the diff to the user
- If `--apply` was used, note which files were modified

### 4. Handle Errors

Common issues:
- **No OPENAI_API_KEY**: tell user to set it in `~/.env.secrets` or shell env
- **Model not available**: suggest falling back to `o3` or `o4-mini`
- **Timeout**: report partial output if any, suggest breaking task into smaller pieces
- **Sandbox denial**: if Codex needs write access, suggest re-running with `--apply`

## Important Rules

1. **Default to read-only** — never write files unless user explicitly passes `--apply`
2. **Default model is gpt-5.4** — override with `--model`
3. **Always use `--ephemeral`** — don't clutter disk with codex sessions
4. **Timeout at 5 minutes** — Codex can be slow on large tasks
5. **Source env secrets** — run `source ~/.env.secrets 2>/dev/null` before codex to pick up OPENAI_API_KEY
6. **Present output concisely** — don't dump raw logs, summarize what Codex did/suggested
