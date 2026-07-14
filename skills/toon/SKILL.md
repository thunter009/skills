---
name: toon
description: Convert JSON to TOON before reading it into context to cut tokens; decode TOON back to JSON losslessly.
when-to-use:
- large JSON tool output, token-efficient JSON, convert to TOON, decode TOON
- Before reading uniform/tabular JSON (API list responses, gh --json, td json) into context
allowed-tools: Bash(toon:*)
category: infra
---

# TOON Encode/Decode for Token Economy

`toon` is installed at `~/.cargo/bin/toon` — a native Rust CLI ([Dicklesworthstone/toon_rust](https://github.com/Dicklesworthstone/toon_rust)) for deterministic, lossless JSON↔TOON conversion. TOON (Token-Oriented Object Notation) drops JSON's braces/quotes/repeated keys in favor of indentation and CSV-like tabular rows.

**Use it as a pre-read filter**: pipe large JSON through `toon` and read the TOON instead. Decode is exact — you can always recover the original JSON.

## Quick Reference

```bash
toon data.json                        # Encode JSON → TOON (stdout); .toon input auto-decodes
gh pr list --json ... | toon -e       # Encode from stdin
toon data.json --stats -o data.toon   # Encode + report token estimate (JSON vs TOON)
toon data.toon -d                     # Decode TOON → JSON
toon big.json --key-folding safe      # Collapse single-key nesting: a.b.c: 1
toon messy.toon -d --no-strict        # Lenient decode (tabs, count mismatches)
```

## When It Pays Off (measured on real data)

| Input shape | Savings | Verdict |
|---|---|---|
| Uniform array of flat objects (tabular: `gh pr list`, `td` lists, API rows) | ~30–60% | Always encode |
| Nested objects (per-row sub-objects) | ~15% | Encode if large; flatten first for more |
| Prose-heavy JSON (beads issues, long descriptions) | ~5% | Skip — use `hr-compress` instead |

Rules of thumb:

1. **Encode when**: JSON is >~2 KB AND mostly uniform arrays/rows. Below that, savings don't cover the pipe step.
2. **Skip when**: values are long free text (TOON can't compress prose), or you're about to edit/patch the JSON (work on the original).
3. **Check ROI with `--stats`** when unsure — it prints estimated JSON vs TOON tokens without you reading either.
4. **Flatten before encoding** for max savings: uniform rows of primitives trigger TOON's tabular form (`users[3]{id,name}:` + CSV rows), the biggest win. `jq`-project nested rows down to flat fields first.
5. **JSONL needs wrapping**: `jq -s .` a JSONL file into a single array before encoding.
6. **Complement, not replacement, for `hr-compress`**: `toon` is lossless and shape-based (structured JSON); `hr-compress` is lossy and query-based (logs, prose, mixed dumps).

## Reading TOON

You will also *receive* TOON from tools that emit it natively — `bv --format toon`, mcp-agent-mail `format='toon'`. Read it directly (it's human/LLM-readable); only `toon -d` back to JSON when a downstream script needs real JSON.

Format at a glance:

```text
user:                      # object → indented keys
  id: 1
  name: Alice
tags[3]: red,green,blue    # primitive array → inline CSV with count
users[2]{id,name,active}:  # uniform object array → header + CSV rows
  1,Alice,true
  2,Bob,false
config.database.host: localhost   # key folding (dotted path = nesting)
```

## Gotchas

- Strict decode rejects tabs in indentation, blank lines inside arrays, and count mismatches — `--no-strict` to tolerate hand-edited TOON.
- Token counts from `--stats` are the tool's own estimator, not your model's tokenizer; treat as directional.
- Subagents doing JSON-heavy retrieval should get the same instruction: encode large uniform JSON with `toon` before reading.
