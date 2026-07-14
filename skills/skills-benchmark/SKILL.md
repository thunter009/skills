---
name: skills-benchmark
description: Run the agent-skills benchmark suite in oracle, paired, or live mode.
when-to-use:
- run benchmark, skills benchmark, oracle mode
- When validating benchmark tasks or skill impact
permissions:
- read
- bash
category: testing
projects:
- agent-skills
---

# Skills Benchmark

Run the agent-skills benchmark harness from the repo root.

## Arguments

- No args: run paired mode (default — most useful)
- `oracle`: oracle mode only (verify all solutions pass)
- `paired`: paired mode (with vs without skills, compute delta)
- `live`: live mode (invoke Claude + skill, score output, compare to oracle ceiling)
- `live <skill-name>`: live mode with specific installed skill
- `live --skill-path ./path/to/SKILL.md`: live mode with local SKILL.md
- Task name(s): run specific task(s) only (e.g., `colgrep-find-auth-logic`)
- `--model <model>`: model for live mode (default: haiku)
- `--max-budget <usd>`: max USD per task in live mode (default: 0.50)

## Execution

### 1. Locate benchmark

```bash
# Find the agent-skills repo root (where benchmark/ lives)
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [[ ! -d "$REPO_ROOT/benchmark" ]]; then
  echo "benchmark/ not found in repo root"
  exit 1
fi
cd "$REPO_ROOT"
```

If not found, tell user this must be run from within the agent-skills repo.

### 2. Parse arguments

| Input | Mode | Tasks | Skill |
|-------|------|-------|-------|
| (none) | paired | all | — |
| `oracle` | oracle | all | — |
| `paired` | paired | all | — |
| `live` | live | all | task.toml default |
| `live my-skill` | live | all | `--skill my-skill` |
| `live --skill-path ./X.md` | live | all | `--skill-path ./X.md` |
| `oracle colgrep-find-auth-logic` | oracle | colgrep-find-auth-logic | — |
| `live my-skill add-pytest-coverage` | live | add-pytest-coverage | `--skill my-skill` |

### 3. Run

```bash
cd "$REPO_ROOT" && benchmark/.venv/bin/python -m benchmark.runner --mode <mode> [--tasks <task1> <task2> ...] [--skill <name>] [--skill-path <path>] [--model <model>] [--max-budget <usd>]
```

### 4. Show results

Read `benchmark/results/report.md` and display to user.

- **paired**: highlight delta table (skill value metric)
- **live**: highlight Live vs Oracle table (gap = improvement target)

### 5. Run tests (if user asks or if something failed)

```bash
cd "$REPO_ROOT" && benchmark/.venv/bin/python -m pytest benchmark/test_oracle.py -v
```
