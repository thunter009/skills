---
name: clean
description: 'End-of-work cleanup sweep for a multi-agent repo — safely land genuine unpushed commits, squash open PRs, prune merged branches and worktrees, clean the remote dev box, and dedup session follow-ups. A /clean wrapper that orchestrates the squash-pr, prune-branches, devbox-cleanup, and followup-dedup skills.'
when-to-use:
- '"/clean" / "clean up the repo" / "tidy up and land everything"'
- End of a work session — land pending work and prune accumulated cruft
- '"commit and push, then squash PRs and prune branches"'
category: meta
related-skills:
- devbox-cleanup
- followup-dedup
- prune-branches
- squash-pr
---

# /clean — repo hygiene sweep

A five-phase end-of-work sweep. Each phase is a checkpoint: run it, report, move on.
`/clean` is the wrapper — the heavy lifting is delegated to focused skills.

## Before you start

- Identify the repo's integration branch (`dev` / `main`) from the contributor docs
  (CLAUDE.md, AGENTS.md).
- **Shared-checkout check.** Are other Claude sessions sharing this working tree? This
  changes Phase 1's path.

  ```bash
  pgrep -fa claude | awk '{print $1}' | sort -u | while read pid; do
    lsof -p "$pid" 2>/dev/null | awk '/cwd/{print $NF}' | grep -qx "$(pwd)" \
      && echo "sister Claude shares this checkout: PID $pid"
  done
  ```

  If sisters are present, never move a shared branch pointer and never run
  `checkout` / `reset` / `rebase` in the canonical checkout — do branch-mutating
  work in a `git worktree`.

- Register with Agent Mail if the repo uses it — mutating ops follow.

## Phase 1 — Land genuine unpushed work

The path depends on the shared-checkout check above.

### Single-agent repo (no sisters)

A dirty working tree IS unlanded work; an "ahead" branch IS your unpushed commits.
Stage, commit, and `git push`. Skip the classifier below — it is just friction here.

### Multi-agent shared checkout (sisters present)

Do **not** assume a dirty working tree or an "ahead" branch is unlanded work. A sister
may have already committed your "modification" and pushed it; your "ahead" commits may
be content-equivalent duplicates of commits already on `origin`. Classify first:

1. **Working-tree changes.** For each modified file, compare its blob to the integration
   branch on the remote:

   ```bash
   git fetch origin <branch> --quiet
   git hash-object <file>                  # working-tree blob
   git rev-parse origin/<branch>:<file>    # remote blob
   ```

   A file whose blob equals `origin/<branch>`'s is already shipped — a sister committed
   it. It is stale residue, not new work. Do not re-commit it.

2. **"Ahead" commits.** For each commit in `origin/<branch>..<branch>`, classify:
   - **Duplicate** — same `git patch-id` as a commit already on `origin`. Drop it.
   - **Already-shipped** — `git cherry origin/<branch> <commit>` prints a `-` prefix,
     meaning its patch-id matches one on the upstream. Drop it.
   - **Genuinely unpushed** — real work not on `origin`. Land it.

3. **Land genuine commits without disturbing a shared branch.** Create an isolated
   worktree at the remote tip, cherry-pick the genuine commits oldest-first, and
   fast-forward push. Never force-push a shared branch; never move the local branch
   pointer that sister sessions share:

   ```bash
   git worktree add --detach <tmp-worktree> origin/<branch>
   git -C <tmp-worktree> cherry-pick <genuine-commit> ...
   git -C <tmp-worktree> push origin HEAD:<branch>
   git worktree remove <tmp-worktree>
   ```

   Resolve `.beads/issues.jsonl` conflicts as positional only — keep both sides' beads,
   never drop a bead another commit added.

If there is genuinely nothing to land, say so and move on — do not manufacture a commit.

## Phase 2 — Squash open PRs

Invoke the **`squash-pr`** skill. It lists open PRs, presents them for triage, and
squash-merges the approved ones through GitHub's merge path. No open PRs → no-op; report
and continue.

## Phase 3 — Prune branches and worktrees

Two passes — remote first, then local. They use different tools because their skills do.

### Remote branches

Invoke the **`prune-branches`** skill. It cross-references GitHub PR state to find
merged and squash-merged branches on `origin`, categorizes the rest, and proposes an
explicit delete command for approval. `prune-branches` is remote-only — it does not
touch local refs.

### Local branches and worktrees

`prune-branches` does not handle these; inline the logic here. Enumerate candidates:

```bash
SKIP='dev|main|master'   # plus any other integration branches the repo uses
INTEG='dev'              # the one integration branch to compare against

# local branches that are merged, squash-merged, or whose remote is gone
for b in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
  echo "$b" | grep -qxE "$SKIP" && continue
  tracking=$(git for-each-ref --format='%(upstream:track)' "refs/heads/$b")

  reason=""
  if [ "$tracking" = "[gone]" ]; then
    reason="remote branch deleted (squash-merged)"
  elif git merge-base --is-ancestor "$b" "origin/$INTEG" 2>/dev/null; then
    reason="ancestor of origin/$INTEG (rebase-merged)"
  elif cherry_out=$(git cherry "origin/$INTEG" "$b" 2>/dev/null); then
    if ! echo "$cherry_out" | grep -q '^+'; then
      reason="all patch-ids on origin/$INTEG (squash-merged rebase branch)"
    fi
  fi

  [ -n "$reason" ] && echo "deletable: $b — $reason"
done

# worktrees whose branch is in the deletable set are removable
git worktree list
```

The third predicate (`git cherry` returns and `grep '^+'` finds no unique commits)
catches **squash-merged rebase branches** whose tips are not ancestors of
`origin/$INTEG` but whose patch-ids all are. Critically, the `elif cherry_out=$(...)`
guard means a `git cherry` *failure* (e.g. `origin/$INTEG` does not exist) leaves
`reason` empty — the branch is NOT classified as deletable on an error. Every
"deletable" line carries an explicit reason for the user to audit.

Then, with user confirmation:

```bash
git worktree remove <wt>          # plain (no --force) — fails loudly if dirty
git branch -D <merged-branch>     # -D because not always an ancestor of HEAD
```

For repos with extensive accumulation (dozens of branches, many worktrees), delegate to
**`git-worktree-branch-rationalization`** instead — it harmonizes content from variants
onto a staging branch before destructive cleanup. `/clean` is for routine end-of-session
tidy, not branch archaeology.

## Phase 4 — Clean the remote dev box

If the project has a checkout on a remote box (e.g. reachable via `ssh dev-box`), invoke
the **`devbox-cleanup`** skill: it tears down a stale swarm, verifies unpushed work is
superseded, resets the remote checkout, and restarts its services. Skip this phase if
the project has no remote box.

To detect: look in `~/.ssh/config` for a host the project's docs reference, or check
recent session logs / project memory for a known dev-box hostname.

## Phase 5 — Follow-ups

Collect follow-ups discovered **during this session's work only** — this is not a general
backlog sweep. Resolve them create-by-default (CLAUDE.md Session Completion rule 7): easy
wins from this session's work get done now; for the rest, invoke the **`followup-dedup`**
skill before creating anything — extract entity keywords, search Todoist / Beads / Linear,
surface candidates inline. Update an existing tracker item rather than spawning a parallel
one; route genuinely new items per followup-dedup's **Tracker-routing rules** (canonical —
includes Todoist Inbox-section placement + cold-start standard). Do not open new beads or
tasks for unfinished scope — finish that now or hand it off. If a tracker file is reserved
by a live sister agent, hand the content to that agent instead of fighting the reservation.

## Output

Close with a per-phase summary table:

| Phase | Result |
|---|---|
| 1 Land work | pushed N commits / nothing to land |
| 2 Squash PRs | merged #N… / no open PRs |
| 3 Prune | deleted N branches, M worktrees |
| 4 Dev box | cleaned / no remote box / skipped |
| 5 Follow-ups | updated bd-… / none |

## Guardrails

- **In a shared checkout, classify before you commit.** A diff is not always unlanded
  work; an "ahead" commit is not always unique. Blob-compare and `patch-id` first.
- **Never force-push** a shared branch; **never move a branch pointer** sister sessions
  share — use a worktree.
- **Confirm destructive steps** (branch deletes, remote reset) before running them.
- Each delegated skill keeps its own confirmations — do not bypass them.
- `/clean` is a session sweep, not a backlog tool: Phase 5 is session follow-ups only.
