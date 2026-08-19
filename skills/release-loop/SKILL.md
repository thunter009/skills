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

Arms a recurring job that decides *whether to release* from commit velocity, snapshots the integration branch into a release PR, and — if the PR is obviously clean — merges it itself.

Merging `main` fires release automation (semantic-release, prod deploys). Whether the loop does that itself or leaves it for a human is a **policy choice** (see "Auto-merge vs stop-at-PR" below). The safe default is stop-at-PR; but once operators tire of hand-merging every obviously-green release, the loop can self-merge under a strict gate — that's usually what a mature loop ends up doing.

## Why a velocity gate instead of a fixed interval

A fixed 4h cron releases three times on a quiet Sunday and once during a busy afternoon — exactly backwards. Instead, tick often and *gate*:

- Tick every 2h (cheap, mostly no-ops).
- Release only if the integration branch is **≥5 commits ahead** of production, **or** **≥4h since the last release with ≥1 commit**.

Busy periods hit the commit threshold and release at ~4h. Quiet periods drift to 6h+ or skip entirely. One knob, both behaviors.

## Do NOT promote dev→main. Cut a release branch off dev, PR that to main.

This is the load-bearing design decision, and getting it wrong produces a loop that **can never release**.

The obvious design is "promote `dev → main` directly" (rebase dev onto main, rebase-merge, resync dev). It doesn't work in an active repo:

- Promotion-style releases **rewrite `dev`** (rebase + force-push sync), which **retargets or orphans** every open PR against it — so they must stop whenever any PR targets the integration branch.
- In any repo with real throughput, `dev` is *never* free of open PRs. New ones arrive faster than they land.

So the promotion can never run. Field data: three consecutive ticks released nothing while the backlog grew to 50 commits, and during a single tick the open-PR count went **up**, 4 → 5, with three PRs opened within ten minutes. A treadmill, not a queue.

(As of 2026-07-24 `/release` itself uses this same frozen-ref cut — Form 1 below — and fast-forwards `main` to the cut SHA instead of rebase-merging, so it never rewrites `dev` and no longer stops on open dev PRs. The loop and `/release` now produce identical artifacts; the loop's remaining job is the cadence gate. **Merge the loop's release PRs with `/release` Step 5b's ff push, not `gh pr merge --rebase`** — a rebase-merge re-SHAs `main` and is exactly what forces Form 2 below.)

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

## Auto-merge vs stop-at-PR

Stop-at-PR (loop opens the release PR, a human merges) is the safe default, and the right starting point. But in a repo with real throughput it creates a new failure mode: **releases pile up waiting for a keystroke.** Observed: a green, mergeable release PR sat ~8 hours while the genuinely-new backlog behind it grew from 10 commits to 38 — the loop correctly refused to cut a second PR while one was pending, so nothing shipped until someone hand-merged. An obvious green release shouldn't need a human.

So once the operator opts in, let the loop **self-merge its own release PR** under a strict gate — where "merge" means performing `/release` Step 5b's fast-forward push, not clicking a merge button. Fold it into the top of the tick: before cutting anything, if a release PR is already open, try to land it instead —

- Land = **`/release` Step 5b's fast-forward push of the frozen cut SHA to production**: `git push origin "${CUT_SHA}:refs/heads/${PROD}"` (plain push, no force — a fast-forward by construction; GitHub then auto-marks the release PR `MERGED`). **Never `gh pr merge --rebase`** (and never any `gh pr merge` / UI merge): GitHub's rebase-merge mints new SHAs on `main`, which breaks the `main`-is-ancestor-of-`dev` invariant the ff-cut design depends on and drags you back into rewriting `dev` — the exact root cause `/release` was rebuilt to kill. Do the push **only if ALL hold**: `mergeable == MERGEABLE`, `mergeStateStatus == CLEAN`, every check `pass` (the release-lane `commit-lint` exemption showing `skipping` is fine), **zero unresolved review threads**, and no skip-ci token on the head commit — then re-check `git merge-base --is-ancestor origin/$PROD $CUT_SHA` immediately before the push (if `main` moved since the freeze, STOP and re-cut per Step 3; do not force). Then **run the fold (below)** and END the tick — the next tick cuts the next batch once `main` settles.
- **Fold, every time you land.** The ff-push is only half of landing. semantic-release then writes `chore(release): X [skip ci]` (plus CHANGELOG, release notes, version bumps) onto production, and **nothing else ever moves it back** — the loop is the only actor, so a skipped fold is a permanent gap. Perform `/release` Step 6 before ending the tick: wait for the release workflow's back-commit to appear on `origin/$PROD`, then fold it into `$INT` per that step (ff-push when `$INT` is behind-only, rebase-forward in a private worktree when not). If the back-commit has not landed yet, do **not** silently skip — end the tick with an explicit `fold pending: <sha> on $PROD` note so the next tick picks it up before cutting anything.

  This is the loop's single highest-consequence omission. An automated cut that never folds diverges production from integration by one commit per release, silently, forever: three unfolded `chore(release)` commits accumulated across a single day of autonomous cuts (a private data-platform repo, 2026-08-12) and were only caught by a human asking why the branches had drifted.
- Still-pending CI → report "waiting on CI", END. Don't cut, don't merge.
- Red / conflicting / unresolved findings / skip-ci token → do **not** merge; report the specific blocker and leave it for a human.

**Why a review re-check on the release PR is *not* required:** a release PR is a cherry-pick (or snapshot) of commits **already reviewed and merged** into the integration branch. The upstream reviews are the gate; the release PR just promotes vetted content. So a review bot that *skips or rate-limits* the release PR itself does **not** block the merge (zero unresolved threads confirms nothing is outstanding). This is the one place a "review skipped" green check is safe to honor — precisely because the review already happened upstream. Do **not** generalize this to feature PRs, where the bot *is* the review.

Scope the authority tightly: the loop auto-merges **only its own `release/<date> → main` PRs**. Never integration-branch PRs (their owners merge them), never `dev→main` promotions (those re-diverge dev). This keeps a runaway loop from ever touching work it didn't create.

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

**3. Pre-flight.** `git log --merges origin/main..origin/dev` must be empty if the repo enforces linear history. Expect production to carry a semantic-release back-commit (`chore(release): X [skip ci]` plus CHANGELOG/release notes) that the integration branch lacks — a **single** such commit, from the cut you just landed, is **normal**, not a blocker; a rebase-merge replays over it cleanly. Don't mistake it for a broken branch.

**But check the backlog — by content, not by counting.** An unfolded backlog on production is real: cutting on top of one is how a one-commit drift becomes an eight-commit one. The test that catches it must ask whether production carries *content* the integration branch lacks:

Ask it **per file**, about `$PROD`'s net change since the merge base. That change is already on `$INT` when any of these hold — check them in this order, cheapest first:

1. the file has identical content on both branches now
2. `$PROD` never changed it since the merge base
3. that exact blob appears somewhere in `$INT`'s history for the path (`$INT` had it, then moved on)
4. `git apply --cached --reverse --check` of the patch succeeds against `$INT`'s tree
5. every line the change introduces is already present in `$INT`'s copy of the file

None of the introduced lines present ⇒ drift: block, and name the file. Some present ⇒ a rework: warn, do not block. A worked implementation with a mutation-proven test suite is `scripts/release_backlog_drift.sh` in a private data-platform repo.

**Per file, not per commit.** Per-commit evaluation re-examines superseded states — two old release bumps flagged as drift purely because those version strings no longer appear anywhere on `$INT`, which had moved on to a later version. Only a file's *latest* state can be missing.

**Undecidable warns; it does not block.** The costs are not symmetric. A false block stops every release cycle until a human intervenes; a false pass lets drift grow for one cycle, which the fold step catches. Print every warning and count every skipped path, so a quiet exclusion cannot read as full coverage.

Three tempting tests are all wrong, each verified against live branches rather than reasoned about:

- **Counting commits in `$INT..$PROD`** (defer on >1 back-commit or any non-`chore(release)` commit) counts SHAs, so **a hotfix merged straight to production deadlocks it permanently** — the same fix reaching `$INT` later carries a different SHA, so the range never empties, while a version-comparing fold detector reports "fold not needed". Seen in a private data-platform repo (bd-j23fp): 41 commits stranded, armed loop, passing gate.
- **Whether `$PROD` merges cleanly into `$INT`** asks about a direction the cut never performs. Both-sides edits are the normal post-release state, and a tracker file like `.beads/issues.jsonl` diverges every release, so it reports "human must reconcile" on a cut that loses nothing. Same repo, bd-gdaza — the fix for the bug above, which reintroduced the stall one layer down.
- **A per-file three-way merge** conflicts when the branches touched merely *adjacent* lines. A version bump beside a dependency bump is enough.

Exclude tracker artifacts that both sides always edit, by explicit path list rather than pattern, and report what was skipped.

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
