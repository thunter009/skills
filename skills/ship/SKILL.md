---
name: ship
description: 'Run the full landing workflow: sync, test, split commits, and open a PR.'
when-to-use:
- ship, land this work, prepare PR
- When changes are ready to land
allowed-tools:
- Bash
- Read
- Write
- Edit
- Grep
- Glob
- AskUserQuestion
category: release
related-skills:
- pr-review
- release
---

# /ship: Fully Automated Ship Workflow

## Scope

`/ship` = **feature branch → PR → merge to dev**. Use when a feature is done and ready to land.

To release dev → main, use `/release` after shipping.

---

You are running the `/ship` workflow. This is **non-interactive and fully automated**. Do NOT ask for confirmation at any step. The user said `/ship` which means DO IT. Run straight through and output the PR URL at the end.

**Only stop for:**
- On `main`/`master` branch (abort)
- Merge conflicts that can't be auto-resolved (stop, show conflicts)
- Test failures (stop, show failures)
- Pre-landing review finds CRITICAL issues (ask per-issue)

**Never stop for:**
- Uncommitted changes (always include them)
- Commit message wording (auto-compose)
- Multi-file changesets (auto-split into bisectable commits)

---

## Step 1: Pre-flight

1. Check the current branch. If on `main` or `master`, **abort**: "You're on main. Ship from a feature branch."

2. Run `git status` (never use `-uall`). Note uncommitted changes — they will be included automatically.

3. Determine the integration branch to ship into. Prefer repository-specific workflow docs (README, CLAUDE.md, AGENTS.md, developer instructions) over GitHub's default branch. Examples:
   - If repo policy says `feature/* -> dev`, use `dev`
   - If repo policy says feature branches merge directly to `main`, use `main`

4. If repo docs do not specify an integration branch, detect the base branch from the remote HEAD:
   ```bash
   git symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's|^origin/||'
   ```
   Use the detected branch as `$BASE` throughout. Fall back to `main`.

5. Run `git diff $BASE...HEAD --stat` and `git log $BASE..HEAD --oneline` to understand what's being shipped.

---

## Step 2: Fetch & Rebase Base Branch (BEFORE tests)

Fetch and rebase `$BASE` into the feature branch so tests run against the merged state:

```bash
git fetch origin $BASE
git rebase origin/$BASE
```

**If there are merge conflicts:** Try to auto-resolve if trivial (lockfile regeneration, formatting). If conflicts are complex or ambiguous, **STOP** and show them to the user.

**If already up to date:** Continue silently.

---

## Step 3: Detect & Run Tests

Detect the project's test runner by checking for these markers (in priority order):

| Marker | Test Command |
|--------|-------------|
| `Makefile` with `test` target | `make test` |
| `package.json` with `"test"` script | `npm test` or `yarn test` (check lockfile) |
| `Cargo.toml` | `cargo test` |
| `pytest.ini` / `pyproject.toml` [tool.pytest] / `setup.cfg` [tool:pytest] / `conftest.py` | `pytest` |
| `go.mod` | `go test ./...` |
| `.pre-commit-config.yaml` | `pre-commit run --all-files` (lint gate, not full tests) |
| `Gemfile` with `rspec` | `bundle exec rspec` |
| `Gemfile` with `minitest` / `test/` dir | `bundle exec rails test` or `ruby -Itest` |

Run all detected test suites. If multiple runners exist (e.g., pytest + pre-commit), run them in sequence.

**If any test fails:** Show the failures and **STOP**. Do not proceed.

**If all pass:** Continue — note pass counts briefly.

**If no test runner detected:** Warn the user ("No test runner detected — skipping tests") and continue.

---

## Step 4: Pre-Landing Review

Review the diff for structural issues that tests don't catch. Reuses the `/pr-review` checklist.

1. Read the pr-review checklist at `skills/pr-review/references/checklist.md` (resolve relative to the skills install root). If the file cannot be read, warn and continue — do not block ship for a missing checklist.

2. Run `git diff origin/$BASE...HEAD` to get the full diff.

3. Apply the review checklist in two passes:
   - **Pass 1 (CRITICAL):** SQL & Data Safety, Race Conditions & Concurrency, LLM Output Trust Boundary
   - **Pass 2 (INFORMATIONAL):** All remaining categories

4. Output a summary: `Pre-Landing Review: N issues (X critical, Y informational)`

5. **If CRITICAL issues found:** For EACH critical issue, use AskUserQuestion with:
   - The problem (`file:line` + description)
   - Your recommended fix
   - Options: A) Fix it now, B) Acknowledge and ship anyway, C) False positive — skip
   If user chose A on any issue: apply fixes, stage the fixed files, then re-run tests (Step 3) to verify fixes don't break anything.

6. **If only informational issues:** Output them and continue. They go into the PR body.

7. **If no issues:** Output `Pre-Landing Review: No issues found.` and continue.

Save review output for the PR body in Step 7.

---

## Step 5: Stage All Changes

Stage changes that should be shipped. **Do NOT use `git add -A`** — it can include .env files, credentials, or large binaries. Stage specific files:

```bash
git add <specific-files>
```

Use `git status` to identify what needs staging. If many files changed, stage by directory (e.g., `git add src/ tests/`) rather than blanket-adding everything.

---

## Step 6: Commit (Bisectable Chunks)

**Goal:** Create small, logical commits that work well with `git bisect`. Each commit must be independently valid — no broken imports, no references to code that doesn't exist yet.

### Analyze & Group

1. Run `git diff --cached --stat` and `git diff --cached` to see what's staged.

2. Group changes into logical commits. Each commit = one coherent change, not one file.

3. **Commit ordering** (earlier commits first, dependencies before dependents):
   - **Infrastructure:** migrations, config, CI, dependency changes
   - **Models & core logic:** data models, services, utilities (with their tests)
   - **Interface layer:** controllers, views, CLI commands, API endpoints (with their tests)
   - **Documentation & cleanup:** README changes, comments, formatting

4. **Splitting rules:**
   - A module and its test file go in the same commit
   - Config/infrastructure changes that enable a feature go before the feature
   - If total diff is small (< 50 lines across < 4 files), a single commit is fine — don't over-split

### Commit Each Group

For each logical group:

```bash
git reset HEAD  # unstage all
git add <specific-files-for-this-group>
cat > /tmp/commit-msg.txt <<'EOF'
<type>: <summary>

<optional body — what and why, not how>
EOF
git commit -F /tmp/commit-msg.txt
```

**Write the message to a file; never `-m "$(cat <<'EOF' ... EOF)"`.** `dcg`
blocks the command-substitution form (`heredoc.posix:eval-dynamic`) because it
assembles the shell launcher dynamically. A plain heredoc into a file is fine.

Types: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`

**Only the final commit** gets the co-author trailer:

```bash
cat > /tmp/commit-msg.txt <<'EOF'
<type>: <summary>

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
git commit -F /tmp/commit-msg.txt
```

### Verify Each Commit

After creating each commit, verify it's independently valid:
- For compiled languages: check that it compiles (`cargo check`, `go build ./...`, `tsc --noEmit`)
- For interpreted languages: check imports resolve (quick smoke test)
- If verification fails: fold the commit into the next one rather than shipping a broken bisect point

---

## Step 7: Push & Create PR

### Push

```bash
git push -u origin $(git branch --show-current)
```

**Never force push.** If push is rejected (remote has new commits), rebase and retry once.

### Create PR

```bash
cat > /tmp/pr-body.md <<'EOF'
## Summary
<concise bullet points of what changed and why>

## Pre-Landing Review
<findings from Step 4, or "No issues found.">

## Test Results
- <test runner>: <pass count> passed

## Test plan
- [x] Tests pass on rebased $BASE
- [x] Pre-landing review complete

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF

gh pr create --title "<type>: <summary>" --body-file /tmp/pr-body.md
```

**Use `--body-file`, not `--body "$(cat <<EOF ...)"`** — same `dcg` block as the
commit message above, and it fires after the branch is already pushed.

**Output the PR URL** — this is the final output the user sees.

---

## Important Rules

- **Never skip tests.** If test runner is detected and tests fail, stop.
- **Never force push.** Regular `git push` only.
- **Never ask for confirmation** except for CRITICAL review findings (one AskUserQuestion per critical issue).
- **Split commits for bisectability** — each commit = one logical change, ordered by dependency.
- **Merge conflicts and test failures are the only hard stops** (plus critical review issues).
- **The goal is: user says `/ship`, next thing they see is the PR URL.**
