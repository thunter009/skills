---
name: release-loop
description: Arm a self-pacing release loop that cuts a release branch (snapshot or cherry-pick) off dev and opens a release PR on a velocity-gated cadence.
when-to-use:
- release loop, release cadence, release every N hours
- "set up a loop to release every 4-6 hours"
- When you want unattended release-PR prep without unattended prod merges
permissions:
- bash
- read
category: release
related-skills:
- release
- ship
- squash-pr
---

# Release Loop

Arms a recurring job that decides *whether to release* from commit velocity, snapshots the integration branch, and leaves a release PR for a human to merge.

The loop never merges to the production branch. Merging `main` is what fires release automation (semantic-release, prod deploys), so it stays an operator decision. Everything upstream of that is safe to automate.

## Why a velocity gate instead of a fixed interval

A fixed 4h cron releases three times on a quiet Sunday and once during a busy afternoon — exactly backwards. Instead, tick often and *gate*:

- Tick every 2h (cheap, mostly no-ops).
- Release only if the integration branch is **≥5 commits ahead** of production, **or** **≥4h since the last release with ≥1 commit**.

Busy periods hit the commit threshold and release at ~4h. Quiet periods drift to 6h+ or skip entirely. One knob, both behaviors.

## Do NOT promote dev→main. Cut a release branch off dev, PR that to main.

This is the load-bearing design decision, and getting it wrong produces a loop that **can never release**.

The obvious design is "run `/release`, promote `dev → main`." It doesn't work in an active repo:

- `/release` **stops** when any PR targets the integration branch — correctly, because promoting typically **recreates or force-moves `dev`** (auto-delete-on-merge, force-push sync), which **retargets or orphans** every open PR against it.
- In any repo with real throughput, `dev` is *never* free of open PRs. New ones arrive faster than they land.

So the promotion can never run. Field data: three consecutive ticks released nothing while the backlog grew to 50 commits, and during a single tick the open-PR count went **up**, 4 → 5, with three PRs opened within ten minutes. A treadmill, not a queue.

Instead the loop cuts a release branch that does **not** move `dev`, and PRs *that* to `main`. Two forms, and which one you need depends on whether `dev` still descends from `main`:

### Form 1 — snapshot (when `dev` descends from `main`)

```bash
AGENT_NAME=release-loop git push origin origin/dev:refs/heads/release/$(date +%Y-%m-%d)
```

A pure ref push — no checkout, nothing touches the shared tree. Simple and clean **as long as `git merge-base --is-ancestor origin/main origin/dev` is true.**

### Form 2 — cherry-pick (when `dev` has DIVERGED from `main`)

The snapshot has one fatal precondition: `dev` must descend from `main`. **The instant someone merges a `dev→main` promotion, that breaks** — the promotion rebase-replays most of dev's history onto `main` under *new* SHAs, so `dev` and `main` now share content but not ancestry. A snapshot of dev's tip then conflicts against `main` on all that duplicated content, and **every future snapshot conflicts too** until `dev` is realigned. This is not hypothetical — it happened (releases #928 and #942, both cut as snapshots, both `CONFLICTING`; `git cherry` showed 67 of dev's 69 commits were already on `main` by content).

The realign-`dev` fix (rebase dev onto main, force-with-lease) is usually **wrong** for a hot integration branch: a live swarm's SHAs churn constantly, a force-move races their pushes and forces every open PR to rebase. Instead, make the release **content-addressed** — pick only what's genuinely new:

```bash
# in a PRIVATE worktree cut from origin/main (never the canonical checkout):
git worktree add .ntm/worktrees/cp-$(date +%F) origin/main
cd .ntm/worktrees/cp-$(date +%F) && git switch -c release/$(date +%Y-%m-%d)
# Pick ONE COMMIT AT A TIME, redirecting from a file — NOT a pipe, NOT `cherry-pick $ORDER`:
git rev-list --reverse --right-only --cherry-pick origin/main...origin/dev > /tmp/rl_order.txt
conflict=""
while IFS= read -r sha; do
  git cherry-pick "$sha" || { conflict="$sha"; git cherry-pick --abort; break; }
done < /tmp/rl_order.txt
if [ -n "$conflict" ]; then
  echo "CONFLICT on $conflict — aborting release"
  cd - && git worktree remove --force .ntm/worktrees/cp-$(date +%F); exit 0   # report + END, push nothing
fi
git merge-tree $(git merge-base HEAD origin/main) HEAD origin/main | grep -c '^<<<'   # must be 0
```

`git cherry` / `--cherry-pick` compare by **patch-id (content), not SHA**, so this is immune both to the divergence *and* to dev's SHA churn — it snapshots the genuinely-new *content* at cut time, no matter how many times the swarm rebased dev underneath. It never force-moves `dev`, so the swarm and the open dev PRs are untouched. This is the mechanism to reach for whenever `dev` is a busy shared branch; Form 1 is just its degenerate case when ancestry is intact.

**Cherry-pick one commit at a time — but redirect the loop from a file, not a pipe, and not `git cherry-pick $ORDER`.** Two traps stack here:

- `git cherry-pick $ORDER` (collect SHAs in a var, expand unquoted) assumes the shell word-splits on newlines. Interactive `zsh` does **not** split an unquoted parameter expansion, so it passes all SHAs as a *single* argument and dies with `fatal: ambiguous argument`.
- `git rev-list … | while read sha; do …; done` runs the loop body in a **pipeline subshell**. A conflict handler that does `exit` there exits only the subshell — the outer script keeps going to the verify + push steps and can push a *partially* cherry-picked branch (the already-applied commits are internally clean, so the `merge-tree` conflict check passes on the partial set and hides the abort). Redirect from a file instead (`done < /tmp/order.txt`): the loop then runs in the current shell, so `break` + a `conflict` flag actually stop the release, and you can clean up the worktree before ending.

Recompute the list against **current** `origin/main` right before picking — in a busy repo a release can fire and `dev` can rebase during your setup, desyncing a list captured a few seconds earlier.

Release branches are **immutable** in both forms: if one exists for today, cut `-2`, `-3`, … rather than force-moving it.

**Push the branch ref from the canonical checkout, not the worktree** — a fresh worktree has no virtualenv, so a pre-push hook that runs the test suite (`pytest`) fails to spawn. `git push origin release/<date>:refs/heads/release/<date>` from canonical uses the real env.

## No ship pass — let the PR owners merge their own work

An early version of this loop squash-merged green, reviewed dev PRs itself, on the theory that clearing the queue was the precondition for releasing. Once you cut release branches instead, that precondition evaporates — and in practice the ship pass was losing a race anyway: the agents that owned the PRs merged them within minutes of CI going green, so the loop mostly arrived late to PRs that were landing regardless, while carrying real risk of merging someone else's work under them.

Drop it. The loop cuts release branches; PR owners merge PRs. If you want a merge gate that refuses PRs with unresolved HIGH findings, that belongs in branch protection or a review bot — not in a cron job that only bites when it wins a race.

## The tick

Each firing runs four stages and stops at the first blocker:

**1. Velocity gate.** Compute and short-circuit before doing any work:

```bash
git fetch origin
N=$(git rev-list --count origin/main..origin/dev)
LAST=$(git log -1 --format=%ct origin/main)
AGE_H=$(( ($(date +%s) - LAST) / 3600 ))
# release iff: N >= 5, OR (AGE_H >= 4 AND N >= 1)
```

If the gate fails, log `deferring — N commits, AGE_H h since last release` and end. A deferred tick should be silent and cheap.

**2. Skip if a release PR is already open** against production. Don't stack releases the operator hasn't merged yet — report the existing URL and end.

**3. Pre-flight.** `git log --merges origin/main..origin/dev` must be empty if the repo enforces linear history. Expect production to carry a semantic-release back-commit (`chore(release): X [skip ci]` plus CHANGELOG/release notes) that the integration branch lacks — that divergence is **normal**, not a blocker; a rebase-merge replays over it cleanly. Don't mistake it for a broken branch.

**4. Cut + PR, then stop.** Ref-push the snapshot, open the PR, report the URL, **do not merge**.

## Arming it

Cron jobs created from inside a coding-agent session are typically **session-only** — in-memory, gone when the session exits, often auto-expiring after a few days. Say so plainly when you arm one; the user will otherwise assume it's a daemon. If the loop must survive session death, arm it as a real system cron / launchd job that shells out to the agent CLI instead.

Pick an off-minute (`13 */2 * * *`, not `0 */2 * * *`) so the fleet doesn't stampede the API on the hour.

The prompt you schedule must be **fully self-contained** — it fires into a fresh context with no memory of the conversation that armed it. It needs the repo path, the gate arithmetic, the cut-don't-promote mechanism, and an explicit "do not ask the user anything."

## Before you arm

Report these to the user first; they change whether the loop is worth arming:

- How far ahead the integration branch already is, and when the last release actually shipped.
- That the job is session-only and dies with the pane.
- That the loop stops at the PR — nothing reaches production without them.

## Flagging it

A loop the user forgets about is a liability. Flag the pane (`🔁` + label + cadence) and leave a workspace note saying what's running, its cadence, and how to stop it — job ID plus "exiting the session kills it."
