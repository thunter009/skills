---
name: swarm-start
description: Join a swarm, register, triage work, and claim a bead.
when-to-use:
- join swarm, swarm start, register agent
- When entering an active swarm
user_invocable: true
category: infra
---

You are joining an agent swarm. Execute these steps in order:

**Argument parsing**: Extract from `$ARGUMENTS`:
- `--no-mail` flag — skip Agent Mail registration, coordination, and cleanup. Use this for short-lived sub-agents or solo runs where coordination overhead is wasted.

1. **Load context**: Read AGENTS.md and CLAUDE.md thoroughly. Understand the project, stack, constraints, and quality gates.

2. **Understand the codebase**: Use your code investigation capabilities to understand the architecture, key files, and current state. Read the main entry points and recent git history.

3. **Register with Agent Mail** (skip if `--no-mail`): Call `macro_start_session` with:
   - `human_key`: the current project path
   - `program`: your program name (e.g. `claude-code`)
   - `model`: your model name
   - `task_description`: "joining swarm for $ARGUMENTS"

   **Save the response.** Hold `agent.name` and `registration_token` for the entire session — needed to deregister cleanly at session end (step 9).

4. **Check coordination state** (skip if `--no-mail`): Fetch your Agent Mail inbox. Acknowledge any messages from other agents. Note who else is active and what they're working on. swarm-start is opportunistic — exactly one inbox check on startup, exactly one on completion (step 8). If `fetch_inbox` returns a transient pattern (`Database connection pool exhausted`, `Too many open files. Freed <N> cached repos`), wait 5s and retry the same tool call; if still transient, 15s then 45s; after 3 retries treat Agent Mail as unavailable per the CLAUDE.md "proceed normally" rule. (`mcp-agent-mail` is JSON-RPC, not a CLI, so this is a conversational retry policy — see `skills/shared/retry-mcp.sh` for the reference implementation. Client-side mitigation tracks bd-j1x; server-side fix in `mcp-agent-mail` is bd-9nd.)

5. **Find highest-impact work**: Run `bv --robot-triage` to get graph-aware recommendations. Pick the top-ranked bead that doesn't conflict with other agents' active work.

   **If you were handed an external claim list** (marching orders, user instruction, drafted swarm-wave prompt): do NOT trust it blindly. Drafted prompts can list "claimable parallel" beads that still have open blockers — the dep state at draft time may not match now. For each bead in the list, run `br show <id>` and check the `Dependencies:` section. If any blocker is still OPEN, skip that bead (or escalate to the dispatcher) — claiming a blocked bead burns a context cycle when you discover it can't move. Also confirm the bead's referenced test file path actually exists; marching orders may use forward-looking names.

   **Verify the bead's premise before claiming** (up to ~5 min): check its core factual claims against the live tree/system — does the file, table, or mechanism it describes exist at HEAD in the state the bead assumes? Stale or fictional premises are common in beads written weeks earlier. If stale: update the bead with current state, then proceed from reality or skip if moot.

6. **Claim and start**: `br update <id> --status in_progress`. If `--no-mail`, skip the Agent Mail announce/reserve. Otherwise announce your claim via Agent Mail thread `[br-<id>]`, and if the bead involves editing files, reserve them via Agent Mail.

7. **Work the bead**: Implement the task. Run quality gates before committing. Run `ubs` on changed files.

   **Decision budget**: at a design fork, pick the reversible option consistent with the PRD/ADRs, record choice + rationale in the PR/bead comment, keep going. Stop and escalate ONLY for: irreversible/destructive actions, new external spend, product/positioning calls, or schema/contract changes.

   **Merge gate**: follow the gate stated in your marching orders. If the orders are silent, the default is conditioned self-merge — squash-merge your own PR only when CI is green AND code review (codex/CodeRabbit) has no unresolved HIGH findings; never merge a red or unreviewed PR. An explicit "do NOT merge — operator merges" in the orders always wins.

8. **Complete**: `br close <id>`. If `--no-mail`, skip the announcement; otherwise announce completion via Agent Mail. Check `bv --robot-next` for the next bead.

9. **Session end (only if leaving the swarm, and only if this session registered in step 3)**: `release_file_reservations(project_key, agent_name)` then `deregister_agent(project_key, agent_name, registration_token)` with the token saved in step 3. Best-effort — a failed call must not block exit; log and continue. **Deregister, don't retire** — retirement leaves the agent in the roster and accumulates contact-approval rows that block future broadcasts. Never use `hard_delete_agent` here.

**Do NOT get stuck in "communication purgatory"** — be proactive about starting work. Inform other agents what you're doing, don't wait for permission.

**After context compaction**: Immediately re-read AGENTS.md. This is mandatory.
