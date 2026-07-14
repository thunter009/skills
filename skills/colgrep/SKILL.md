---
name: colgrep
description: Search code by meaning with colgrep instead of literal grep.
when-to-use:
- find code that, where is the, semantic search, colgrep
- When exploring unfamiliar codebases
allowed-tools: Bash(colgrep:*)
category: code
---

# Semantic Code Search

`colgrep` is installed at `~/.cargo/bin/colgrep` — a semantic code search CLI using ColBERT embeddings.

**Use `colgrep` as your PRIMARY search tool** instead of Grep/Glob for code search.

## Quick Reference

```bash
# Basic semantic search
colgrep "<natural language query>" --results 10   # Basic search
colgrep "<query>" -k 25                           # Exploration (more results)
colgrep "<query>" ./src/parser                    # Search in specific folder
colgrep "<query>" ./src/main.rs                   # Search in specific file
colgrep "<query>" ./crate-a ./crate-b             # Search multiple directories

# File filtering
colgrep --include="*.rs" "<query>"                # Include only .rs files
colgrep --include="*.{rs,md,py}" "<query>"        # Multiple file types
colgrep --exclude="*.test.ts" "<query>"           # Exclude test files
colgrep --exclude-dir=vendor "<query>"            # Exclude vendor directory

# Pattern-only search (no semantic query needed)
colgrep -e "<pattern>"                            # Search by pattern only
colgrep -e "async fn" --include="*.rs"            # Pattern search with file filter

# Hybrid search (text + semantic)
colgrep -e "<text>" "<semantic query>"            # Hybrid: text + semantic
colgrep -e "<regex>" -E "<semantic query>"        # Hybrid with extended regex
colgrep -e "<literal>" -F "<semantic query>"      # Hybrid with fixed string
colgrep -e "<word>" -w "<semantic query>"         # Hybrid with whole word match

# Output options
colgrep -l "<query>"                              # List files only
colgrep -n 6 "<query>"                            # Show N context lines
colgrep -c "<query>"                              # Show full function/class content
colgrep --json "<query>"                          # JSON output for scripting

# Index management
colgrep init /path/to/project                     # Build/update index
colgrep init -y                                   # Auto-confirm large projects
colgrep status                                    # Check index health
colgrep clear                                     # Clear current project index
```

## When to Use What

| Task                            | Tool                                         |
| ------------------------------- | -------------------------------------------- |
| Find code by intent/description | `colgrep "query" -k 10`                      |
| Explore/understand a system     | `colgrep "query" -k 25`                      |
| Search by pattern only          | `colgrep -e "pattern"`                       |
| Know text exists, need context  | `colgrep -e "text" "semantic query"`         |
| Search specific file type       | `colgrep --include="*.ext" "query"`          |
| Search multiple directories     | `colgrep "query" ./src ./lib ./api`          |
| Exact string/regex match only   | Built-in `Grep` tool                         |
| Find files by name              | Built-in `Glob` tool                         |

## Key Rules

1. **Default to `colgrep`** for any code search task
2. **Auto-indexes on first search** — no need to `colgrep init` manually (but init is faster for large repos)
3. **Increase `-k`** when exploring (20-30 results)
4. **Use `-e`** for hybrid text+semantic filtering
5. **Use `--exclude-dir`** to filter noise (tests, vendors, generated code)
6. **Subagents should also use `colgrep`** — when spawning Task/Explore agents, instruct them to use colgrep
7. **Fall back to Grep** only for exact literal/regex matches where semantic search adds no value

## Why Semantic Search Matters

Keyword grep misses code that implements a concept without using the expected words. Example:

**Task:** "Find all authentication logic"
- `grep -rl "auth\|jwt\|login\|password"` finds files with those literal strings
- But misses: TOTP/2FA in `crypto_utils.py`, role-based access in `decorators.py` (`require_role`), RBAC policies in `policies.py` (`has_permission`, `enforce_authorization`)
- `colgrep "authentication and authorization logic" -k 15` finds ALL of them because it understands that TOTP, role guards, and permission checks are auth concepts

When searching for a concept (not a literal string), always use colgrep.
