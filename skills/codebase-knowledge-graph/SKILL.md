---
name: codebase-knowledge-graph
description: Build an interactive knowledge graph of any codebase via the Understand-Anything pipeline, with a batch-integrity guard the raw plugin lacks.
when-to-use:
- knowledge graph, understand codebase, codebase map, onboarding graph, architecture graph
- When onboarding to an unfamiliar/large repo and you want a visual node-graph + guided tour
- When you want /understand output but from the CURRENT session (not a fresh plugin-loaded one)
user_invocable: true
category: code
---

Build a knowledge graph (`.understand-anything/knowledge-graph.json`) + interactive dashboard for a target codebase by orchestrating the **Understand-Anything** (UA) plugin pipeline from this session.

Why this wrapper instead of the plugin's own `/understand`:
- Runs from ANY session — UA's skills only auto-load in a fresh plugin-loaded session.
- **Enforces batch integrity.** UA's `file-analyzer` agents self-clean stale output with a `rm batch-<i>*.json` glob; for batch 1 that glob ALSO matches `batch-10/11/12.json`, silently deleting them so the merge runs on a graph missing whole batches with no error. This skill verifies every batchIndex has output before merging and re-runs any gap.
- Surfaces the token cost up front and offers local-model init.

**Target:** `$ARGUMENTS` = project path (default: current working directory). For huge monorepos, pass a subdir.

---

## Phase 0 — Preconditions

1. **UA plugin installed?**
   ```bash
   claude plugin list 2>/dev/null | grep -q understand-anything || {
     claude plugin marketplace add Egonex-AI/Understand-Anything
     claude plugin install understand-anything
   }
   ```
2. **Resolve paths + build core** (idempotent; needs Node ≥22 + pnpm ≥10):
   ```bash
   source skills/codebase-knowledge-graph/scripts/ua-env.sh   # exports PLUGIN_ROOT, SKILL_DIR
   ```
   If `pnpm` is missing, stop and tell the user to install Node ≥22 + pnpm ≥10.
3. **Token-cost gate.** The first build re-reads the whole codebase across parallel agents — ~1.5M agent tokens per ~15k LOC in practice. If the project is large (>100 files), tell the user and offer: (a) scope to a subdir, (b) point UA's model provider at a local model (Ollama / local MLX) for init, (c) proceed. Incremental re-runs are cheap.

## Phase 1 — Scan + batch (deterministic, UA's own tree-sitter scripts)

Read the target's `package.json`/manifest + README to get `name`, a 1–2 sentence `description`, and confirmed `frameworks`. Then:

```bash
skills/codebase-knowledge-graph/scripts/scan.sh \
  "<PROJECT_ROOT>" "<name>" "<description>" "<framework1,framework2,...>"
```

This runs `generate-ignore.mjs` → `scan-project.mjs` → `extract-import-map.mjs`, assembles `intermediate/scan-result.json`, and runs `compute-batches.mjs`. It prints the file count, complexity, and the batch list (`N` batches). Note `N`.

## Phase 2 — Analyze (the LLM phase)

Dispatch one **file-analyzer** subagent per batch, **up to 5 concurrent**. Each agent must read and obey UA's agent definition at `$PLUGIN_ROOT/agents/file-analyzer.md`, read its batch from `intermediate/batches.json` (the object whose `batchIndex` == its number), run `extract-structure.mjs`, and write `intermediate/batch-<i>.json` (or `batch-<i>-part-<k>.json` if it splits).

> **Include this guard in every dispatch prompt:** "If you clean stale output, delete ONLY the exact `batch-<i>.json` / `batch-<i>-part-*.json` for YOUR index — never a `batch-<i>*` glob (it matches batch-10/11/12)."

Dispatch prompt template per batch — fill PROJECT_ROOT, SKILL_DIR (`$SKILL_DIR`), PLUGIN_ROOT, project name/description/languages, and the batchIndex.

## Phase 2.5 — Integrity guard (the point of this skill)

After all batches return, BEFORE merging:
```bash
skills/codebase-knowledge-graph/scripts/verify-batches.sh "<PROJECT_ROOT>"
```
Exit 0 = every batchIndex has output. Non-zero = it prints the MISSING indices — re-dispatch a file-analyzer for each missing index (with the glob guard), then re-run until clean. Do NOT proceed to merge with gaps.

## Phase 3 — Merge

```bash
python3 "$SKILL_DIR/merge-batch-graphs.py" "<PROJECT_ROOT>"
```
Writes `intermediate/assembled-graph.json`. Note the `Output: N nodes, M edges` line and sanity-check N against the sum of per-batch node counts.

## Phase 4 — Architecture layers

Dispatch an **architecture-analyzer** subagent (obey `$PLUGIN_ROOT/agents/architecture-analyzer.md`). Tell it to read the language/framework context files under `$SKILL_DIR/languages/<lang>.md` and `$SKILL_DIR/frameworks/<fw>.md` for the detected langs/frameworks, read `intermediate/assembled-graph.json` (all file-level nodes + edges), assign every file-level node to exactly one layer, and write `intermediate/layers.json` (`id`,`name`,`description`,`nodeIds`).

## Phase 5 — Guided tour

Dispatch a **tour-builder** subagent (obey `$PLUGIN_ROOT/agents/tour-builder.md`). Inputs: `intermediate/assembled-graph.json` (file-level nodes + edges), `intermediate/layers.json`. Output: `intermediate/tour.json` (ordered steps: `order`,`title`,`description`,`nodeIds`), dependency-ordered.

## Phase 6 — Assemble + validate

```bash
skills/codebase-knowledge-graph/scripts/assemble.sh "<PROJECT_ROOT>"
```
Merges nodes/edges + layers + tour + project metadata into `.understand-anything/knowledge-graph.json` and `meta.json`, drops dangling layer/tour refs, and reports node/edge/layer/tour counts + dangling-edge count (must be 0).

## Phase 7 — Dashboard

```bash
DASH="$PLUGIN_ROOT/packages/dashboard"
( cd "$DASH" && PNPM_CONFIG_VERIFY_DEPS_BEFORE_RUN=false pnpm install --config.dangerouslyAllowAllBuilds=true >/dev/null 2>&1 )
( cd "$DASH" && GRAPH_DIR="<PROJECT_ROOT>" npx vite --host 127.0.0.1 ) &   # prints tokenized URL
```
Capture the `🔑 Dashboard URL: http://127.0.0.1:<PORT>?token=<TOKEN>` line and give the user the FULL tokenized URL. Inside atrium, open it in a browser pane (`atrium browser open <url>`) and screenshot to confirm it renders; an onboarding modal covers the graph on first load — dismiss "Don't show again" before screenshotting.

## Done

Report: graph location, node/edge/layer/tour counts, dashboard URL. Note that `.understand-anything/` is committable for team reuse EXCEPT `intermediate/` and `diff-overlay.json` (add those to `.gitignore`). Token spend was the first-build cost; later runs are incremental.

**Gotchas**
- Glob-collision deletion is the headline failure — Phase 2.5 exists for it. Never skip it.
- pnpm 11 blocks native build scripts by default; `ua-env.sh` passes `--config.dangerouslyAllowAllBuilds=true` so tree-sitter bindings compile.
- Don't pipe a destructive `&&` chain through `tail`/`head` (swallows exit codes); `ua-env.sh` avoids it.
