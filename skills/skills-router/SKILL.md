---
name: skills-router
description: Advisory UserPromptSubmit hook that suggests 2-3 matching skills per prompt.
when-to-use:
- installing or tuning the skills-router hook
- prompts keep missing the right skill, mis-dispatch
- which skill should handle this
allowed-tools: Bash(*)|Read
category: infra
---

# Skills Router

A UserPromptSubmit hook that classifies user intent with keyword heuristics
(no LLM, <100ms) and injects a one-line advisory naming 2-3 candidate skills.
With ~250 deployed skill descriptions competing for attention, the advisory
narrows dispatch to the likely category. Advisory only: it never blocks a
prompt, never rewrites it, and says "ignore if not" right in the hint.

## How it works

- `scripts/hook.sh` — hook entry point. Reads the UserPromptSubmit JSON from
  stdin, bypasses slash commands (already dispatched), empty and <5-char
  prompts, then emits `hookSpecificOutput.additionalContext`. Decisions log
  to `~/.cache/skills-router/decisions.jsonl`. `SKILLS_ROUTER_QUIET=1`
  silences it entirely.
- `scripts/classify.sh` — pure-bash keyword classifier over the 8 categories
  in `setup/categories.json` (code, testing, web, pm, release, infra, docs,
  meta) plus direct skill-name aliases (a prompt that says "linear" routes to
  /linear regardless of category race). Cap: 3 candidates. `--batch` mode
  classifies one prompt per stdin line in a single process; `--list-categories`
  prints the supported category set.
- `scripts/benchmark.sh` — accuracy over `fixtures/test-cases.jsonl`
  (labeled prompts across all 8 categories); exits nonzero under 80%.

## Install / verify

```bash
setup/hooks.sh          # registers the hook in ~/.claude/settings.json (idempotent)
setup/verify.sh         # includes a skills-router registration check
```

## Tune

Add keywords to the per-category pattern blocks or the alias table in
`classify.sh`, add a labeled case to `fixtures/test-cases.jsonl`, then:

```bash
scripts/benchmark.sh    # must stay >= 80%
bash tests/test_skills_router.sh
```

## Caveats

- Heuristic, not semantic: it suggests, the model decides. False positives
  are cheap (one advisory line); false negatives just mean no hint.
- Keyword tables are curated in `classify.sh`, not generated from
  `categories.json` — a unit test pins the category LIST to categories.json
  so new categories can't silently go unrouted, but new skills only surface
  via the alias/default tables.
