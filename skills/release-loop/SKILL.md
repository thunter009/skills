---
name: release-loop
description: Arm a self-pacing release loop that cuts an immutable release branch and opens a release PR on a velocity-gated cadence.
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

## Cut an immutable release branch — do NOT promote dev→main

This is the load-bearing design decision, and getting it wrong produces a loop that **can never release**.

The obvious design is "run `/release`, promote `dev → main`." It doesn't work in an active repo, for a reason that only shows up in production:

- `/release` **stops** when any PR targets the integration branch — correctly, because promoting typically **recreates or force-moves `dev`** (auto-delete-on-merge, force-push sync), which **retargets or orphans** every open PR against it.
- In any repo with real throughput, `dev` is *never* free of open PRs. New ones arrive faster than they land.

So the promotion can never run. Field data from the loop that motivated this skill: three consecutive ticks released nothing while the backlog grew to 50 commits, and during a single tick the open-PR count went **up**, 4 → 5, with three PRs opened within ten minutes of each other. That is a treadmill, not a queue — grinding harder on the PR backlog does not converge.

**Instead, snapshot and PR the snapshot:**

```bash
AGENT_NAME=release-loop git push origin origin/dev:refs/heads/release/$(date +%Y-%m-%d)
gh pr create --base main --head "release/$(date +%Y-%m-%d)" ...
```

A pure ref push — no checkout, no rebase, nothing touches the shared working tree. `dev` is never recreated, so open dev PRs are completely unaffected, and **releasing stops depending on PR churn entirely.**

Release branches are **immutable**: if one already exists for today, cut `-2`, `-3`, … rather than force-moving it. A release branch that moves under a reviewer is the same class of bug as recreating `dev`.

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
