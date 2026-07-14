---
name: multi-round-research
description: "Two-round parallel-subagent research that produces an opinionated proposal, then challenges and surpasses it. Use for deep concept exploration, design-space mapping, build-vs-buy decisions, or any 'research this from every angle and tell me what to do' question."
when-to-use:
- multi-round research, deep research, research from every angle
- spawn subagents to research, challenge and surpass, dueling research
- When you want an opinionated proposal that has survived an adversarial second pass
user_invocable: true
allowed-tools: Bash(codex:*)|Bash(gemini:*)|Bash(timeout:*)|Bash(mkdir:*)|Bash(pgrep:*)|Bash(sleep:*)|Bash(mv:*)|Bash(cat:*)|Bash(date:*)|Bash(ls:*)|Bash(tr:*)|Read|Write|Glob|Agent
category: web
related-skills:
- codex
---

# /multi-round-research — Two-Round Parallel Subagent Research

Research a concept from every angle with a fan-out of parallel subagents, write a
single **opinionated, creative proposal**, then spawn a fresh round whose only job
is to **challenge and surpass** that proposal — updating it only where round 2
genuinely improves on round 1.

This is *not* a balanced literature review. The deliverable is a point of view that
took a stance, got attacked, and held or improved. Hedging is a failure mode.

> Pattern credit: Riley Coyote (@RileyRalmuto). The defining move is the round-2
> mandate: each fresh subagent's job is to *challenge and surpass* what round 1
> already produced — not to re-research the topic.

## Prerequisites

- `TAVILY_API_KEY` in the environment — the web-research scripts (`search.sh`,
  `extract.sh`, `research.sh`) all exit 1 without it. Subagents inherit the
  orchestrator's env, so set it once at the parent level. Get a key at
  <https://tavily.com>.
- A writable cwd — `--output` and the `.research/` log dir land in `pwd`.
- For `--engine codex|gemini` only: GNU coreutils for `timeout` (preinstalled on Linux;
  macOS users: `brew install coreutils`). Skip this prereq when running the default
  `claude` engine — it has no shell-level timeout.

## Arguments

```
/multi-round-research <concept or question>          # full 2-round run, claude engine, 4 agents
/multi-round-research <concept> --agents 5           # fan-out width per round (3–5, default 4)
/multi-round-research <concept> --engine codex       # claude (default) | codex | gemini
/multi-round-research <concept> --rounds 3           # total rounds incl. build (default 2 = 1 build + 1 challenge; rarely >3)
/multi-round-research <concept> --output proposal.md # where the proposal lands (default ./research-proposal.md)
/multi-round-research <concept> --model <model>      # engine model override
/multi-round-research <concept> --dry-run            # print the angle assignment + prompts, spawn nothing
```

Parse from `$ARGUMENTS`:
- The concept/question (everything not a flag). If empty, ask the user what to research — do not invent one.
- `--engine <claude|codex|gemini>` (default `claude`)
- `--agents N` (default 4; clamp to 3–5 — fewer than 3 misses angles, more than 5 dilutes synthesis)
- `--rounds N` (total rounds incl. the build round; **N ≥ 1**, reject ≤ 0; default 2 → 1 build + 1 challenge; `--rounds 1` skips the challenge entirely)
- `--output PATH` (default `./research-proposal.md`)
- `--model <model>` (engine default: codex=`gpt-5.4`, gemini=default, claude=subagent default)
- `--dry-run` flag

## How the rounds differ

| Round | Subagents' mandate | Orchestrator's job |
|-------|--------------------|--------------------|
| **1 — Build** | Each agent owns a distinct *angle* and researches it hard. Returns findings + a position. | Synthesize the surviving angles into one opinionated proposal that takes a stance (drop angles that failed, timed out, or returned nothing useful — see Step 2). |
| **2+ — Challenge** | Each agent reads the *current proposal* and tries to break or beat it from its angle. Returns concrete, sourced improvements — or "nothing to add, and here's why it holds." | Apply only changes that genuinely surpass round 1. Leave unchallenged sections verbatim. |

The round-2 discipline is the whole point: **change for change's sake is forbidden.**
A section survives untouched unless a challenger produced something demonstrably better.

## Workflow

### 1. Frame the concept and assign angles

**Pre-flight:** fail loud if `TAVILY_API_KEY` is unset — subagent web research
silently degrades to "couldn't find anything" outputs otherwise, and the operator
only notices from the empty proposal:

```bash
[ -n "$TAVILY_API_KEY" ] || { echo "TAVILY_API_KEY unset — see Prerequisites" >&2; exit 1; }
```

Restate the concept in one sentence so the user can confirm scope. Then split it into
`--agents N` **distinct, non-overlapping angles** — each agent gets a lens nothing else
covers. Tailor angles to the concept; the defaults below are a starting kit, not a fixed list:

- **Prior art / state of the art** — what already exists, who's done it, what's proven
- **First-principles / contrarian** — ignore convention; what does the problem actually demand
- **Failure modes & risks** — how this goes wrong, hidden costs, what bites in 6 months
- **Adjacent fields** — how a different domain solved the structurally-similar problem
- **Practitioner reality** — constraints from actually shipping/operating it (cost, ops, team)

**Slugify** each angle for filesystem-safe use, in two steps:
1. **Abbreviate to a unique stem** — pick the shortest prefix that distinguishes
   this angle from the others. The example defaults abbreviate before the first
   slash or qualifier ("Prior art / state of the art" → "prior art", "Failure
   modes & risks" → "failure modes").
2. **Normalize**: lowercase; replace whitespace and any `/`, `&`, or other
   shell-meaningful chars with `-`; collapse repeated `-`.

The example defaults end up as: `prior-art`, `first-principles`, `failure-modes`,
`adjacent`, `practitioner`. Substituting the raw "Prior art / state of the art"
directly into `r${ROUND}-${ANGLE}.log` would create a subdirectory and break the
redirect — always slug before substituting.

Print the angle→agent mapping (raw name + slug) to the conversation so the user can
sanity-check coverage before any subagents fan out. The mapping also gets written into
`--output` later (as the `<!-- angles: … -->` comment in the Step-2 template, using
the slugs) so round 2 knows what round 1 was *supposed* to cover — don't create the
file here; Step 2 produces it.

**Build the per-angle prompts.** What follows differs by engine:

- **`--engine claude`**: hold the constructed prompts in orchestrator memory
  (one per angle); pass them directly to each `Agent` call in Step 2. No
  `.research/` writes are needed for the claude path.
- **`--engine codex` / `--engine gemini`**: write each prompt to a file so the
  concurrent dispatch subshells can `cat`-source it (bash 3.2 has no associative
  arrays — per machine portability rules — so a per-slug file is the portable
  carrier across forked subshells). Create `.research/` on first run:

  The block below is a **syntactically-valid stub** — it parses and runs but
  produces obviously-useless `.prompt` files. The orchestrator must substitute
  `ANGLES` with the concept's actual slugs and `PROMPT_FOR` with a real
  per-angle prompt emitter before this becomes the real dispatch input:

  ```bash
  mkdir -p .research
  ANGLES=(REPLACE_ME_WITH_SLUGS)             # e.g. (prior-art first-principles failure-modes ...)
  PROMPT_FOR() { echo "REPLACE_ME_WITH_PROMPT — angle=$1"; }
  for ANGLE in "${ANGLES[@]}"; do
    PROMPT_FOR "$ANGLE" > ".research/r1-${ANGLE}.prompt"
  done
  ```

  The `REPLACE_ME_*` sentinels parse cleanly as bash but are deliberately
  ugly so a literal run yields visibly-broken prompt files (the engine logs
  show `REPLACE_ME_WITH_PROMPT — angle=…` instead of research findings, which
  is loud failure rather than silent garbage). Substitute both before
  dispatching for real. The default slug list shown above is concept-agnostic
  example output, never the right answer for *your* concept.

If `--dry-run`, print the angle list **and** the constructed prompts (for the
codex/gemini path, concatenate the just-written `.prompt` files; for the claude
path, print the in-memory prompts), and stop without fanning out.

### 2. Round 1 — fan out, then synthesize

Before fanning out: if `--output` already exists, rename it to
`<output>.bak.<YYYYMMDDHHMMSS>` and continue (preserves the prior run's proposal —
silently overwriting a user's earlier work is the kind of pothole this skill should
not dig).

Spawn `N` subagents **in parallel** (see *Engine dispatch* below), one per angle. Each
agent prompt must include:
- The concept (verbatim) and its single assigned angle
- "Research with real sources. Cite every non-obvious claim with a URL."
- "Be opinionated: end with a clear position and your top 2–3 recommendations for this angle. Do not hedge."
- The web-research tool paths (subagents cannot invoke skills — see *Web research*).
- "Return: findings (bulleted, sourced), your position, open questions you couldn't resolve."

When the surviving agents return (claude path: all `Agent` calls completed; codex/
gemini path: `wait` returned and the survival gate didn't abort the round),
**synthesize** — do not concatenate. **Exclude failed-angle logs**: the codex/gemini
path's `.log.timeout` / `.log.failed` files are quarantined for a reason (the
"Synthesizing partial-failure rounds" anti-pattern below), and a claude `Agent` that
returns "I couldn't find anything" counts as a failed angle too — drop it and note
the slug for the Step 4 report. Resolve contradictions between angles explicitly
(name the tension, pick a side, say why). Produce `--output`:

```markdown
# Proposal: <concept>
<!-- angles: prior-art, first-principles, failure-modes, adjacent, practitioner -->

## Position
<the opinionated stance — what we should do, in 2–4 sentences>

## Rationale
<why, drawing the strongest threads from each angle, with citations>

## Recommendation
<concrete next steps / design / decision>

## Risks & open questions
<what could break this; what round 1 couldn't resolve>

## Sources
<deduped citation list>
```

### 3. Round 2+ — challenge and surpass

Spawn `N` **fresh** subagents (do not reuse round-1 agents' context — "fresh" is what
buys the adversarial perspective; no per-agent angle rotation is needed). Reuse the
round-1 angle set; each round-2 agent takes one angle and attacks the **whole
proposal** from that lens (not a single section). Each prompt must include:
- The **full current proposal** (the file content)
- The agent's single assigned angle
- "Your job is to challenge and surpass this proposal. Find what's wrong, weak, dated,
  or unambitious from your angle. Propose something demonstrably better, with sources."
- "If the proposal already holds on your angle, say so explicitly and explain why it's
  hard to beat — do not invent a change to look productive."
- "Return: per-claim verdict (holds / weak / wrong), and for each `weak` or `wrong`
  verdict a concrete, sourced replacement."

For the `codex` / `gemini` path, write each per-angle round-2 prompt to
`.research/r${ROUND}-${ANGLE}.prompt` (where `ROUND` is the current round number,
2 or higher) before invoking the dispatch loop from *Engine dispatch*. The loop
`cat`-sources by `$ROUND` + `$ANGLE`, so the prompt files **must exist** — a
missing file means `cat` returns empty, the engine runs with an empty prompt, and
you get an empty/garbage log without an error. The `claude` path needs no separate
file step — the orchestrator passes the prompt directly to each `Agent` call.

Then **revise with discipline**. Map each agent verdict to a changelog label:

| Agent verdict | Changelog label | When |
|---------------|-----------------|------|
| `holds` | **Held** | Always — agent saw no weakness from their angle |
| `weak` | **Changed** | Challenger's replacement demonstrably beats r1 |
| `weak` | **Rejected** | Replacement is "different not better" |
| `wrong` | **Changed** | Always — wrong must be fixed, even if the challenger's replacement is imperfect |

- Apply a change only if a challenger produced something that genuinely beats round 1.
  "Different" is not "better."
- Leave unchallenged or successfully-defended sections **verbatim**.
- Append a changelog under `## Round N changelog` (replace N with the current round
  number — Round 2 is the first challenge round; with `--rounds 3+` you get Round 3,
  Round 4, etc., each with its own changelog section). Record all three label types so
  the final report (Step 4) can count rejected challenges, not just landed ones:

```markdown
## Round N changelog
- **Changed — Position:** <what & why it surpasses r1> (source: …)
- **Held — Risks:** challenged on X, kept because <reason>
- **Rejected — Recommendation:** challenger proposed Y, kept r1 because "different not better" (<why>)
```

If `--rounds 3+`, repeat step 3 against the revised proposal. **Stop early** when every
challenger in the round returns `holds` on every claim they reviewed (no `weak` /
`wrong` verdicts left to map) — convergence, not exhaustion, is the exit.

> **`--rounds 1` short-circuit.** Skip Step 3 entirely and go straight to Step 4.
> The proposal as produced in Step 2 *is* the deliverable — no challenge round, no
> changelog. Use `--rounds 1` for a fast first cut where the round-2 discipline isn't
> warranted (initial scoping, quick recon).

### 4. Report

End with: rounds run, agents per round, **failed/timed-out angles per round** (with
the slugs, so the operator sees which lenses dropped — empty list if all survived),
sections changed vs held, count of challenges rejected as "different not better," and
the path to the final proposal. Do not re-summarize the proposal — point to the file.

## Engine dispatch

**`claude` (default).** Spawn the round's agents as parallel `Agent` calls **in a single
message** (one `Agent` tool use per angle). Each call needs `subagent_type:
"general-purpose"`, a short `description` (3–5 words — "research first-principles
angle"), and the angle prompt. `general-purpose` has the full toolset (Bash for Tavily
scripts, Read/Write, web). Do *not* use `Explore`: that agent is tuned for code-search
across files/directories and won't carry out web research the way this skill needs. The
harness runs the Agent calls concurrently; each agent's final message is its findings.

**`codex` / `gemini`.** Dispatch one engine process per angle in parallel, capped at 2
concurrent (≥3 concurrent `codex exec` / `gemini -p` processes on one host stall —
see the agent-skills bug-hunt contention notes; the gate must count **both** binaries
because a sister gemini run can stall a codex batch and vice versa). Each dispatch
needs three things wrapped together in a backgrounded subshell: the gate, the
`timeout`-bounded engine call, and the exit-code capture that quarantines failed
logs so synthesis doesn't ingest partial output.

Variable roles in the block below:
- `$ROUND` and `$MODEL` are **orchestrator-substituted** before the loop (round
  number; `--model` flag value).
- `$ANGLE` is the **loop variable**, set per iteration by `for ANGLE in
  "${ANGLES[@]}"`.
- `$ANGLE_PROMPT` is **constructed inline** inside each subshell by
  `cat`-sourcing the per-angle `.prompt` file written in Step 1 — it is
  *not* an env var the user (or orchestrator) sets.

Never pipe engine output to `tail` — a full pipe buffer hangs the wrapper.

```bash
mkdir -p .research

# Host-wide gate: counts BOTH codex and gemini processes
running() {
  echo $(( $(pgrep -f '^codex exec' | wc -l) + $(pgrep -f '^gemini -p' | wc -l) ))
}

# One backgrounded subshell per angle. The subshell isolates $? per call —
# without it, the parent's $? after `&` is the spawn exit (0), not the engine
# exit, and the timeout/failure detection silently never fires.
for ANGLE in "${ANGLES[@]}"; do
  while [ "$(running)" -ge 2 ]; do sleep 5; done
  (
    LOG=".research/r${ROUND}-${ANGLE}.log"
    ANGLE_PROMPT="$(cat ".research/r${ROUND}-${ANGLE}.prompt")"
    # codex: read-only research, ephemeral session, 10-min/angle ceiling
    timeout 600 codex exec -m "${MODEL:-gpt-5.4}" --sandbox read-only \
      --skip-git-repo-check --ephemeral "$ANGLE_PROMPT" > "$LOG" 2>&1
    # gemini alternative (pick one engine per invocation, not both):
    # timeout 600 gemini -p "$ANGLE_PROMPT" > "$LOG" 2>&1
    rc=$?
    if [ "$rc" -eq 124 ]; then
      echo "[r${ROUND} ${ANGLE}] TIMED OUT — excluding from synthesis" >&2
      mv "$LOG" "$LOG.timeout"
    elif [ "$rc" -ne 0 ]; then
      echo "[r${ROUND} ${ANGLE}] FAILED rc=$rc — excluding from synthesis" >&2
      mv "$LOG" "$LOG.failed"
    fi
  ) &
done
wait

# Survival gate — abort the round if fewer than ceil(N/2) angles survived.
N=${#ANGLES[@]}
N_REQUIRED=$(( N / 2 + N % 2 ))
N_OK=$(ls .research/r${ROUND}-*.log 2>/dev/null | wc -l | tr -d ' ')
if [ "$N_OK" -lt "$N_REQUIRED" ]; then
  echo "round $ROUND: $N_OK/$N angles survived, need $N_REQUIRED — aborting" >&2
  exit 1
fi
```

`timeout 600` (10 min/angle) bounds a stuck call. Tune up for `--engine codex` on
large topics; tune down for cheap recon. The `claude` engine has no analogous
shell-level cap — prefer it when you want truly unbounded parallel fan-out.

After the dispatch block returns (`wait` plus the survival gate), the orchestrator's
synthesis step reads only the surviving `.research/r${ROUND}-*.log` files —
glob-matching the unrenamed pattern naturally skips quarantined `.log.timeout` /
`.log.failed` siblings.

Read every surviving log back, then synthesize/revise exactly as in the claude path.
Engine choice changes *who researches*, never the two-round structure.

## Web research (for subagents and engines)

Subagents and codex/gemini cannot invoke skills, so pass these script paths into every
research prompt:

| Need | Command |
|------|---------|
| Search | `~/.claude/skills/search/scripts/search.sh '{"query":"…","max_results":5}'` |
| Extract URL(s) | `~/.claude/skills/extract/scripts/extract.sh '{"urls":["…"]}'` |
| Deep research | `~/.claude/skills/research/scripts/research.sh '{"input":"…","model":"mini"}'` |

Prefer these over built-in web tools — they return LLM-optimized output. Require a real
URL behind every non-obvious claim; a proposal built on unsourced assertion is the thing
this skill exists to prevent.

## Anti-patterns

- **Balanced both-sides mush.** The proposal must take a position. If round 1 hedges,
  re-synthesize before round 2.
- **Round 2 rewriting for sport.** Untouched-unless-genuinely-better is the rule. Track
  rejected challenges in the report.
- **Overlapping angles.** Two agents researching the same lens wastes the fan-out. Assign
  distinct, mutually-exclusive angles.
- **Unsourced confidence.** Opinionated ≠ made up. Every non-obvious claim needs a URL.
- **Raising the 5-agent cap.** The 3–5 clamp is in the arg parser for a reason —
  synthesis quality drops faster than coverage rises beyond 5. Add rounds, not width.
- **Synthesizing partial-failure rounds as if complete.** If one or more angles
  timed out, errored, or returned empty/garbage, the synthesis loses coverage of
  that lens. Exclude failed-angle logs (per the codex/gemini exit-code check), tell
  the user which angles dropped, and abort the round if fewer than `ceil(N/2)`
  survived rather than papering over the gap.
- **Concurrent invocations in the same cwd.** Two parallel `/multi-round-research`
  runs in the same working directory clobber each other — both write to
  `.research/r${ROUND}-${ANGLE}.prompt` / `.log` and to the default
  `./research-proposal.md`. Symptom: garbled prompts, log files from the wrong
  concept, intermittently empty findings. Fix: serialize (one run at a time per
  cwd) or invoke each run from a separate directory.
- **Treating a missing verdict as `Held`.** If a round-2 agent returns without
  emitting a clear `holds`/`weak`/`wrong` verdict for a claim (truncated output,
  off-topic response, "I'm not sure"), do not silently default to `Held` — that
  papers over an actual coverage gap. Treat the claim as **unreviewed for that
  angle** and note it in the Step 4 report (slug + which claim was missed); the
  next challenge round can re-attack.
