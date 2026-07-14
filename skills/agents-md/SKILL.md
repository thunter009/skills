---
name: agents-md
description: Create repo-specific AGENTS.md guardrails from the codebase.
when-to-use:
- create AGENTS.md, bootstrap agent instructions
- When a repo needs AI agent guidance
allowed-tools:
- Bash
- Read
- Write
- Edit
- Grep
- Glob
- Agent
- AskUserQuestion
category: infra
---

# Bootstrap AGENTS.md

Generate a project-tailored AGENTS.md, the canonical instruction file for AI coding agents working in a repository.

## What AGENTS.md Is

AGENTS.md is a root-level markdown file that tells any AI coding agent (Claude Code, Codex CLI, Gemini CLI, Cursor, etc.) how to behave in this specific repo. It covers:

- **Safety invariants**: what agents must never do
- **Toolchain**: language runtimes, package managers, build tools
- **Architecture**: repo layout, key modules, data flow
- **Code discipline**: editing rules, file creation policy, backwards compat stance
- **Quality gates**: linters, tests, type checks agents must run
- **Session protocol**: how to land work cleanly so the next agent can pick up

## Process

### Phase 1: Discover the Repo

Run all discovery in parallel where possible. Gather:

1. **Root files**: `ls` the repo root. Look for README, package.json, pyproject.toml, Cargo.toml, go.mod, Makefile, Dockerfile, docker-compose, .env.example, etc.
2. **Existing agent config**: Check for CLAUDE.md, .cursorrules, .cursor/rules/, .claude/settings.json, .github/copilot-instructions.md, CONTRIBUTING.md, .editorconfig
3. **Git info**: default branch name, recent commit style (`git log --oneline -20`), any branch naming conventions
4. **Tech stack detection**:
   - JS/TS: package.json → runtime (node/bun/deno), package manager (npm/yarn/pnpm/bun), framework
   - Python: pyproject.toml/setup.py/requirements.txt → manager (uv/pip/poetry), framework
   - Rust: Cargo.toml → edition, workspace layout
   - Go: go.mod → module path
   - Other: detect from file extensions and build files
5. **Directory structure**: Use Glob (`**/*`) and `ls` to map top-level and second-level directories (skip node_modules, .git, __pycache__, .venv, etc.)
6. **Testing setup**: test runner, test directory, how to run tests
7. **Linting/formatting**: eslint, prettier, ruff, black, clippy, golangci-lint, etc.
8. **CI/CD**: .github/workflows/, .gitlab-ci.yml, Jenkinsfile, etc.
9. **Generated files**: any codegen, build outputs, compiled assets
10. **Issue tracking**: .beads/, Linear config, GitHub Issues conventions

**Check for existing AGENTS.md**: If one already exists, read it first. Ask the user whether to replace it entirely or merge discovered info into the existing structure. Preserve any custom rules or project-specific sections the user already wrote.

### Phase 2: Draft the AGENTS.md

Use the template below, adapting each section to what was discovered. **Omit sections that don't apply.** A Bash-only project doesn't need a "Generated Files" section if there aren't any.

**Key principles:**
- Be specific to THIS repo, not generic
- Include exact commands (not "run the linter" but `ruff check . --fix`)
- State the default branch by name
- List real directories from the repo layout
- Reference actual config files found

### Phase 3: Present and Refine

Show the draft to the user. Ask if anything should be added, removed, or adjusted. Common refinements:
- Adding project-specific forbidden patterns
- Adjusting the strictness of safety rules
- Adding tooling assumptions (what's installed on dev machines)
- Documenting deployment targets

Write the final AGENTS.md to the repo root.

## Template

Below is the canonical template. Adapt every section to the actual repo. Remove sections in `[brackets]` that don't apply. Replace all `{placeholders}`.

~~~markdown
# AGENTS.md: {Project Name}

> Guidelines for AI coding agents working in this codebase.

---

## Safety Rules

### Human Override

The user's instructions take precedence over everything in this file. If the user explicitly asks you to do something that contradicts a rule below, follow the user's instructions.

### No File Deletion

Never delete files or directories without explicit permission from the user in the current session. If something should be removed, ask first.

### No Destructive Git

The following commands are forbidden unless the user provides the exact command and explicit approval:

- `git reset --hard`
- `git clean -fd`
- `rm -rf`
- Any command that can delete or overwrite uncommitted work

Prefer safe alternatives: `git status`, `git diff`, `git stash`, copying to backups.

### No File Proliferation

Never create variant files (`main_v2.ts`, `component_backup.tsx`, `utils_improved.py`). Edit existing files in place. New files are only for genuinely new functionality.

---

## Toolchain

{Describe the exact runtimes, package managers, and build tools. Be prescriptive.}

[Example for JS/TS:]
- **Runtime:** Bun
- **Package manager:** Bun (`bun install`, `bun add`). Never use npm/yarn/pnpm.
- **Lockfile:** `bun.lock` only
- **Target:** Latest Node.js; no legacy compatibility needed

[Example for Python:]
- **Runtime:** Python 3.12+
- **Package manager:** uv (`uv pip install`, `uv sync`). Never use pip directly.
- **Lockfile:** `uv.lock`
- **Virtual env:** `.venv/` (managed by uv)

[Example for Rust:]
- **Edition:** 2024
- **Build:** `cargo build`, `cargo test`
- **Clippy:** All warnings are errors

### Key Dependencies

| Dependency | Purpose |
|------------|---------|
| {dep} | {what it does} |

---

## Architecture

{Brief description of what the project does and its high-level design.}

### Repo Layout

```
{project}/
├── {real directory structure from discovery}
```

### Key Modules

{Describe 3-5 most important modules/directories and their responsibilities.}

---

[## Generated Files

Files in `{path}/` are generated by `{command}`. Never edit them manually.]

---

## Code Discipline

### Editing Rules

- Make changes manually, file by file. No bulk codemods or regex scripts.
- Read sufficient context before editing. Understand the code first.
- Keep changes minimal: fix what's asked, don't refactor surroundings.

### Backwards Compatibility

{Choose one stance and state it clearly:}
- [Early stage:] No backwards compatibility needed. Do things the right way with no tech debt.
- [Mature:] Maintain backwards compatibility. Deprecate before removing.

---

## Quality Gates

**Run these after any code changes, before committing:**

```bash
{exact lint command}
{exact test command}
{exact typecheck command, if applicable}
{exact build command, if applicable}
```

If any check fails, fix the issue before proceeding. Do not skip or silence checks.

---

[## Testing

### Running Tests

```bash
{exact commands to run tests}
```

### Test Structure

| Directory | Coverage |
|-----------|----------|
| {test dir} | {what it tests} |

### Test Policy

- Tests must cover happy path, edge cases, and error conditions.
- {Any project-specific testing rules.}]

---

[## Issue Tracking

{Describe the issue tracking system in use: beads, Linear, GitHub Issues, etc.}

```bash
{key commands for working with issues}
```]

---

## Git Workflow

- **Default branch:** `{main or master}`
- **Commit style:** {describe from git log: conventional commits, imperative, etc.}
- {Any branch naming conventions}
- {Merge strategy: rebase, squash, merge commits}

---

## Landing the Plane

When ending a work session, agents must complete every step:

1. **File issues** for remaining work. Create tickets for anything that needs follow-up.
2. **Run quality gates.** Tests, linters, builds (if code changed).
3. **Update issue status.** Close finished work, update in-progress items.
4. [**Sync issue tracker.** {Export/sync command for the project's tracker.}]
5. **Commit and push.** `git pull --rebase && git add <files> && git commit && git push`
6. **Verify.** `git status` must show clean working tree, up to date with origin.

Work is NOT complete until `git push` succeeds. Unpushed work is stranded locally and invisible to every other agent.

A session is only landable when a future agent can pick it back up from the repo state + AGENTS.md without the human re-explaining the project.
~~~

## Adapting the Template

**For monorepos:** Add a "Workspaces" section listing each package/app and its specific commands.

**For multi-language repos:** Split the Toolchain section by language.

**For projects with deployment:** Add a "Deployment" section with target environments and deploy commands.

**For projects using Agent Mail / multi-agent swarms:** Add coordination rules: file reservations, branch ownership, communication protocols.

**Skill-config block (optional):** Skills that operate on repo state (diagnose, improve-codebase-architecture, plan-review, tdd, swarm-build) work better when the repo declares the things they'd otherwise have to guess. Offer an `## Agent skills` section that pins:
- **Issue tracker**: beads (`br`), Linear, GitHub Issues — and the commands/labels to use
- **Domain docs**: whether `CONTEXT.md` (domain glossary) and `docs/adr/` exist, and the rule for consuming them ("read glossary + nearby ADRs before exploring an area")
- **Triage vocabulary**: the label strings used for triage states, if any

Keep it declarative — one fact per line — so any skill can parse it instead of re-discovering per session.

**For projects with secrets/credentials:** Add a "Secrets" section specifying how to handle env vars, vault access, and what must never be logged.

## What NOT to Include

- Generic advice that applies to all repos ("write clean code")
- Information derivable from reading the code
- Subjective style preferences without enforcement (use linter configs instead)
- Lengthy tutorials; link to docs instead
- Anything already in CLAUDE.md or .cursorrules (reference those files instead of duplicating)
