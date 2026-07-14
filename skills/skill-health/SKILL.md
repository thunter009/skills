---
name: skill-health
description: Validate installed skills, frontmatter, refs, and permissions.
when-to-use:
- skill health, check skills, validate installed skills
- Before publishing skill changes
allowed-tools:
- Bash
- Read
- Glob
- Grep
permissions:
- read
- bash
category: meta
projects:
- agent-skills
related-skills:
- skills-test
---

# /skill-health — Skill Health Dashboard

Scan all installed skills across `skills/` and `.agents/skills/`, validate each is properly configured, and report a summary dashboard.

**Read-only — no modifications.**

## Arguments

| Flag | Default | Description |
|------|---------|-------------|
| (none) | — | Scan all skills in both directories |
| `<name>` | — | Check a single skill by name |
| `--fix` | false | Report suggested fixes for each issue |

## Step 1: Discover Skills

Find all SKILL.md files in both skill roots:

```bash
# Primary skills (this repo)
ls -d skills/*/SKILL.md 2>/dev/null

# Installed agent skills
ls -d .agents/skills/*/SKILL.md 2>/dev/null
```

Build a list of `(name, path, source)` tuples where source is `skills/` or `.agents/skills/`.

If a single `<name>` argument was given, filter to just that skill.

## Step 2: Validate Each Skill

For each SKILL.md, run these checks. Track status as OK, WARN, or ERROR per check.

### Check 1: YAML Frontmatter Valid

- File starts with `---` on line 1
- Has a closing `---` before the markdown body
- Content between delimiters parses as valid YAML (no tabs, no unclosed quotes)

**ERROR** if frontmatter missing or malformed. Skip remaining checks for this skill.

### Check 2: Required Fields Present

Required frontmatter fields:
- `name` — non-empty string
- `description` — non-empty, at least 20 characters

**ERROR** if `name` missing. **WARN** if `description` missing or too short.

### Check 3: Name Matches Directory

The `name` field in frontmatter must match the skill's directory name exactly.

Example: `skills/pr-review/SKILL.md` must have `name: pr-review`.

**ERROR** if mismatch.

### Check 4: Description Quality

- Description is at least 20 characters
- Description is not just the skill name repeated

**WARN** if description is thin.

### Check 5: When-To-Use Populated

The `when-to-use` field should exist and contain at least one trigger phrase.

**WARN** if missing — skill may not be discoverable by the agent.

### Check 6: Referenced Files Exist

Scan the SKILL.md body for paths matching `(scripts|references|templates|fixtures|docs)/...`. For each:

1. Try resolving relative to the skill directory
2. Try resolving relative to the skills root
3. Try resolving relative to the repo root

**ERROR** if any referenced file doesn't exist.

### Check 7: Permissions Declared

Check that the `permissions` field exists in frontmatter. Common values: `read`, `bash`, `write`, `mcp`.

**WARN** if missing — skill may fail at runtime due to undeclared permissions.

### Check 8: Allowed-Tools Format

If `allowed-tools` is present, each entry must match `ToolName` or `ToolName(pattern:*)` format.

**ERROR** if malformed entries found.

## Step 3: Leverage Existing Validation

If `skills/skills-test/scripts/validate.sh` exists, run it for each skill as a cross-check:

```bash
bash skills/skills-test/scripts/validate.sh "$SKILL_PATH" 2>/dev/null || true
```

Parse the JSON output and merge any additional failures into the results. This reuses the Tier 1 static checks from `/skills-test`.

## Step 4: Build Dashboard

Present results as a table sorted by status (ERRORs first, then WARNs, then OK):

```
Skill Health Dashboard
══════════════════════════════════════════════════════════════
SOURCE          SKILL                STATUS  ISSUES
─────────────────────────────────────────────────────────────
skills/         release              ERROR   missing frontmatter
skills/         broken-example       ERROR   name mismatch (got "foo"), refs/bar.md not found
.agents/skills/ old-skill            WARN    no when-to-use, no permissions
skills/         pr-review            OK
skills/         qa                   OK
skills/         ship                 OK
.agents/skills/ linear               OK
.agents/skills/ search               OK
... (remaining OK skills)
─────────────────────────────────────────────────────────────
```

## Step 5: Summary

```
Summary
═══════
Total skills scanned:  48
  skills/:             30
  .agents/skills/:     18

Healthy (OK):          44
Warnings (WARN):        2
Broken (ERROR):         2

Issues found:
  missing frontmatter:  1
  name mismatch:        1
  missing when-to-use:  1
  no permissions:       1
  broken file refs:     1
```

## Step 6: Fix Suggestions (if --fix)

When `--fix` is passed, append a section with concrete fix suggestions:

```
Suggested Fixes
═══════════════
1. skills/release/SKILL.md — Add YAML frontmatter:
   ---
   name: release
   description: Release workflow — rebase dev onto main, create PR, merge
   when-to-use: "release", "ship to main", "merge to main"
   permissions:
     - read
     - bash
   ---

2. .agents/skills/old-skill/SKILL.md — Add when-to-use field:
   when-to-use: |
     - "trigger phrase here"
```

## Guidance

- This is a fast, free check — no API calls, no side effects
- Run before `/skills-test` to catch structural issues cheaply
- Skills with ERROR status will likely fail Tier 1 of `/skills-test`
- WARN items are non-blocking but reduce discoverability or may cause runtime issues
- Both `skills/` and `.agents/skills/` are scanned — this covers repo-local and installed skills
