---
name: codex
description: Run Codex CLI for parallel implementation, review, or second opinions.
when-to-use:
- codex, ask codex, run codex, second opinion
- When you want Codex to inspect or edit in parallel
user_invocable: true
allowed-tools: Bash(codex:*)|Bash(nohup:*)|Bash(source:*)|Bash(mktemp:*)|Bash(kill:*)|Bash(sleep:*)|Bash(cat:*)|Bash(grep:*)|Read
category: code
---

# /codex — Run OpenAI Codex from Claude Code

Delegate a task to OpenAI's Codex CLI agent and return results.

## Arguments

```
/codex <prompt>                    # run task, suggest-only (default)
/codex --apply <prompt>            # run task, apply changes to workspace
/codex --review                    # code review of current changes
/codex --model <model> <prompt>    # override model (default: config.toml `model`)
```

## Workflow

### 1. Parse Arguments

Extract from `$ARGUMENTS`:
- `--apply` flag → use `--sandbox workspace-write` (otherwise `--sandbox read-only`)
- `--review` flag → use `codex exec review --uncommitted` with no `--sandbox` flag; with no target it exits `Error: Specify --uncommitted, --base, --commit, …`
- `--model <model>` → add `-m <model>`; omit `-m` otherwise so `~/.codex/config.toml` `model` applies
- Everything else → the prompt

### 2. Run Codex

Execute Codex CLI non-interactively using `codex exec`, detached, with stdin closed:

```bash
source ~/.env.secrets 2>/dev/null
out=$(mktemp -d)

# Standard task (suggest-only)
nohup codex exec \
  --sandbox read-only \
  --skip-git-repo-check \
  --ephemeral \
  -o "$out/last.md" \
  "<prompt>" </dev/null >"$out/log" 2>&1 &
echo "pid=$! out=$out"

# With --apply (writes to workspace)
nohup codex exec \
  --sandbox workspace-write \
  --skip-git-repo-check \
  --ephemeral \
  -o "$out/last.md" \
  "<prompt>" </dev/null >"$out/log" 2>&1 &
echo "pid=$! out=$out"

# Code review (needs a target: --uncommitted, --base <branch>, or --commit <sha>)
nohup codex exec review \
  --uncommitted \
  --ephemeral \
  -o "$out/last.md" \
  </dev/null >"$out/log" 2>&1 &
echo "pid=$! out=$out"
```

Key flags:
- no `-m` — uses `model` from `~/.codex/config.toml`; add `-m <model>` only for `--model`
- `--sandbox read-only` — safe default for standard exec runs, no file writes
- `--ephemeral` — don't persist codex session files
- `--skip-git-repo-check` — work outside git repos too
- `-o "$out/last.md"` — final agent message; a failed run leaves it missing or empty
- `</dev/null` — closes stdin (trap 2 below)
- `nohup … &` — escapes the Bash tool's 2-minute wait (trap 1 below)

### 3. Wait, Capture & Present Output

- Shell variables do not persist between Bash calls; reuse the printed `pid` and `out` values
- Wait for exit without blocking past 2 minutes. Claude Code: run this with Bash `run_in_background: true`. Other harnesses: re-check `kill -0 <pid>` in short calls.
  ```bash
  for _ in $(seq 60); do kill -0 <pid> 2>/dev/null || break; sleep 5; done
  kill -0 <pid> 2>/dev/null && kill <pid> && echo "TIMEOUT after 5 min"
  ```
- Success = `<out>/last.md` is non-empty. Read it, not the log.
- Failure = `last.md` missing or empty. Read the `ERROR:` or `Error:` line in `<out>/log`. Ignore timestamped MCP-server and model-refresh `ERROR` lines there; successful runs log them too.
- If Codex suggests changes (read-only mode), present the diff to the user
- If `--apply` was used, note which files were modified

### 4. Handle Errors

Common issues:
- **No OPENAI_API_KEY**: tell user to set it in `~/.env.secrets` or shell env
- **Model not available** (`ERROR: The '<model>' model is not supported…`): drop `-m`, or pick a slug from `~/.codex/models_cache.json`
- **Timeout**: report partial output if any, suggest breaking task into smaller pieces
- **Sandbox denial**: if Codex needs write access, suggest re-running with `--apply`
- **Killed or backgrounded at 2 minutes**, **hangs on `Reading additional input from stdin...`**, or **401 from `127.0.0.1:8787`**: see Troubleshooting below

## Troubleshooting: codex exec via the Bash tool

1. **2-minute cap.** The Claude Code Bash tool stops waiting at 2 minutes. A shell `timeout 420` does not extend that limit. On 2026-08-21 the harness killed `codex exec` at 2 minutes (bd-cocy). On 2026-10-28 it moved over-limit calls to the background instead. Fix: the `nohup … &` launch in step 2, then poll. Verified 2026-10-28: a `nohup` run finishes and writes `-o` after its Bash call returns.
2. **stdin hang.** With an open stdin pipe, `codex exec "<prompt>"` prints `Reading additional input from stdin...` and waits for EOF. `codex exec --help` says piped stdin is appended to the prompt. Hooks, loops, and some harnesses pass an open pipe. The Claude Code Bash tool passes `/dev/null`, so the hang does not show there. Repro (2026-10-28, codex-cli 0.165.0): open FIFO stdin → exit 124 under `timeout 25`; `</dev/null` → exit 0. Fix: always pass `</dev/null`. Exception: you pipe the prompt itself (`codex exec - <prompt.md`).
3. **401 from the local proxy.** `~/.codex/config.toml` routes codex through the headroom proxy (`model_provider = "headroom"`, `http://127.0.0.1:8787/v1`). A 401 there looks like a proxy fault. Check in this order:
   1. Does the 401 response carry a `cf-ray` header? Yes: OpenAI's Cloudflare edge rejected the token, and the proxy only relayed the 401. No: the proxy itself failed.
   2. Read the token scopes. This prints the auth mode and `scp` claim only, never the token:
      ```bash
      python3 -I - <<'EOF'
      import base64, json, os
      d = json.load(open(os.path.expanduser("~/.codex/auth.json")))
      p = d["tokens"]["access_token"].split(".")[1]
      print(d.get("auth_mode"), json.loads(base64.urlsafe_b64decode(p + "=" * (-len(p) % 4))).get("scp"))
      EOF
      ```
      A ChatGPT login (`chatgpt`) has `openid profile email offline_access api.connectors.read api.connectors.invoke`, without `api.responses.write` (verified 2026-10-28). `codex login` re-consent returns the same scopes (bd-cocy, 2026-08-22). Do not retry the login.
   3. Fix the provider, not the login. The live config has `requires_openai_auth = true` under `[model_providers.headroom]`. The 2026-08-21 backup `~/.codex/config.toml.bak-headroom-202608211208` lacks it. With it, `codex exec` succeeds through 8787 on the ChatGPT token (2026-10-28). Uncertain: a `headroom wrap codex` re-run can rewrite the block without the line; re-check after one. If the line is present and the 401 stays, the remaining route is an API-key provider (OpenAI or OpenRouter). That is a credential and spend decision; ask the user.

## Important Rules

1. **Default to read-only** — never write files unless user explicitly passes `--apply`
2. **No hardcoded model** — `config.toml` picks it; override with `--model`. Hardcoded slugs go stale (`gpt-5.4` rejected 2026-10-28)
3. **Always use `--ephemeral`** — don't clutter disk with codex sessions
4. **Run detached, stdin closed, 5-minute budget** — `nohup codex exec … </dev/null &`, then poll; never a foreground run
5. **Source env secrets** — run `source ~/.env.secrets 2>/dev/null` before codex to pick up OPENAI_API_KEY
6. **Present output concisely** — don't dump raw logs, summarize what Codex did/suggested
