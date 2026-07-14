---
name: squash-pr
description: Triage open PRs and squash-merge selected ones onto the integration branch.
when-to-use:
- squash PRs, land open PRs, triage PRs
- When clearing a PR queue
permissions:
- bash
- read
- write
category: release
---

# Squash PRs via GitHub Merge

Review all open PRs, present a summary for triage, and squash-merge the ones the user approves through GitHub's PR merge path.

Do **not** land by manually pushing commits and then closing PRs. A landed PR must show as merged, not merely closed.

## Arguments

Parse the user's message for:
- **Specific PR** (optional): PR number or URL. If provided, skip to Step 2 for just that PR.
- **Target branch** (optional): Default = current branch (`git branch --show-current`).

## Step 1: List open PRs

```bash
gh pr list --state open --json number,title,author,headRefName,baseRefName,createdAt,labels,isCrossRepository \
  --jq '.[] | {number, title, author: .author.login, head: .headRefName, base: .baseRefName, age: .createdAt, fork: .isCrossRepository, labels: [.labels[].name]}'
```

Present a table to the user:

| # | Title | Author | Base | Fork? | Age |
|---|-------|--------|------|-------|-----|

Group by category:
- **Dependabot/Renovate** — dependency bumps (safe to batch-land)
- **Feature/fix PRs** — need individual review
- **Stale** — open > 30 days, may need closing

Ask: "Which PRs to squash-merge into `<target>`? (all, numbers, or skip)"

## Step 2: Pre-flight

### 2a: Resolve target branch + detect checkout mode

```bash
git fetch --prune origin
TARGET=$(git branch --show-current)
```

If the user specified a different target branch, set `TARGET` to that name (don't `git checkout` yet — see the mode gate below). If the target doesn't exist locally or on origin, abort: "Branch `$TARGET` not found."

**Squash-merge is a GitHub server-side op — the local sync is incidental.** Skip every local branch-mutating step when the checkout is diverged or shared, otherwise the `--ff-only` pull fails (diverged) or a shared `HEAD` gets corrupted (sister sessions). Detect that up front:

```bash
REMOTE_ONLY=0
# (1) local target not fast-forwardable to origin (has commits origin lacks → ahead or diverged)
AHEAD=$(git rev-list --count "origin/$TARGET..$TARGET" 2>/dev/null || echo 0)
[ "${AHEAD:-0}" -gt 0 ] && REMOTE_ONLY=1
# (2) sister Claude sessions sharing this checkout (shared HEAD) — anchored cwd match, ancestor-excluded
ANCESTORS=" "; p=$$
while [ "$p" -gt 1 ]; do ANCESTORS="$ANCESTORS$p "; p=$(ps -o ppid= -p "$p" | tr -d ' '); done
SISTERS=$(ps -axo pid,command | grep -E "/\.local/bin/claude (--session-id|--resume) " | grep -v grep \
  | while read -r pid _; do
      case "$ANCESTORS" in *" $pid "*) continue;; esac
      lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | grep -qx "n$(pwd)" && echo x
    done | wc -l | tr -d ' ')
[ "${SISTERS:-0}" -gt 0 ] && REMOTE_ONLY=1
echo "TARGET=$TARGET ahead=$AHEAD sisters=$SISTERS REMOTE_ONLY=$REMOTE_ONLY"
```

If `REMOTE_ONLY=1`: do **not** run any local branch-mutating git op (no `git checkout`, stash, or `git pull`). Merges still go through GitHub and merge SHAs are read from `gh`. Tell the user: "Diverged/shared checkout — merging remote-only, leaving the local checkout untouched." `$TARGET` is used only to filter PRs by base branch (Step 3a).

When `REMOTE_ONLY=0` and the user specified a target other than the current branch, switch to it:
```bash
[ "$REMOTE_ONLY" = 0 ] && [ "$TARGET" != "$(git branch --show-current)" ] && git checkout "$TARGET"
```

### 2b: Protect local changes (clean checkout only)

**Skip this entire step when `REMOTE_ONLY=1`.** Check `git status --porcelain`. If dirty:
```bash
[ "$REMOTE_ONLY" = 0 ] && git stash push -u -m "squash-pr: stash before merge sync"
```

Do this **once** before processing any PRs. Do NOT pop until Step 4.

Then update the local target:

```bash
[ "$REMOTE_ONLY" = 0 ] && git pull --ff-only origin "$TARGET"
```

## Step 3: Merge each PR (sequential — complete one before starting the next)

For each selected PR, run 3a through 3c as a unit:

### 3a: Verify target and preview

Fetch PR metadata:

```bash
gh pr view "$PR" --json number,title,baseRefName,headRefName,mergeStateStatus,isDraft,commits
```

If `baseRefName != "$TARGET"`, skip and report: "PR #$PR targets `<base>`, not `<target>`."
If `isDraft == true`, skip and report: "PR #$PR is still draft."

Preview commits and diff:

```bash
gh pr view "$PR" --json commits --jq '.commits[].messageHeadline'
gh pr diff "$PR" --stat
```

Show commit count and headline summary.

### 3b: Squash-merge through GitHub

Use GitHub's PR merge operation:

```bash
gh pr merge "$PR" --squash --delete-branch --subject "<PR title> (#<PR number>)" --body ""
```

Do not use `gh pr close` to mark landed work as done.

After `gh pr merge` succeeds, record GitHub's actual merge commit — and sync the local target **only in a clean checkout**:

```bash
MERGE_SHA=$(gh pr view "$PR" --json state,mergeCommit --jq 'select(.state == "MERGED") | .mergeCommit.oid // ""')
if [ "$REMOTE_ONLY" = 0 ]; then
  git fetch origin "$TARGET"
  git pull --ff-only origin "$TARGET"
fi
if [ -n "$MERGE_SHA" ]; then
  LANDED["$PR"]="${MERGE_SHA:0:7}"   # sourced from gh, not local rev-parse — works in remote-only mode
else
  LANDED["$PR"]="merged-or-queued; merge commit not available yet"
fi
```

If `MERGE_SHA` is empty, do not report the PR as landed. Mark it as queued/pending and re-check later.

### 3c: Merge-block handling

If `gh pr merge` fails:
1. Show the exact GitHub/CLI reason
2. Leave the PR open
3. Ask the user how to proceed: skip this PR, retry after fixing checks/conflicts, or abort batch
4. Do not close the PR manually

## Step 4: Restore and prune

No manual push or close step is needed; GitHub already merged the PR.

Prune deleted remote branches:

```bash
git fetch --prune origin
```

Restore stash if one was created (clean checkout only — `REMOTE_ONLY=1` never stashed):
```bash
[ "$REMOTE_ONLY" = 0 ] && git stash pop
```

If stash pop conflicts, warn the user (their local changes clash with landed PRs).

## Step 5: Summary

Print a results table:

| # | Title | Status |
|---|-------|--------|
| 7 | bump pygments 2.19→2.20 | Merged (abc1234) |
| 12 | fix: typo in README | Skipped (blocked) |

List any PRs left open and why.

## Error recovery

- Merge rejected by GitHub: leave PR open; report reason and ask skip/retry/abort
- Branch protection or merge queue required: do not bypass; use the repo-required path or ask
- `--delete-branch` fails: warn, don't block — the PR is merged
- Local `git pull --ff-only` fails after merge: fetch and report; do not rewrite local history. If it recurs, the checkout is likely diverged — re-run with `REMOTE_ONLY=1` (Step 2a) and skip the local sync entirely
- Stash pop conflicts: warn the user; their local changes clash with the merged PRs
- Diverged or sister-shared checkout (`REMOTE_ONLY=1`): never run `git checkout`/`stash`/`pull`; merge via `gh` and report SHAs from `gh pr view` only — the PRs still land server-side
