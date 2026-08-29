---
name: release-loop
description: Run a velocity-gated release loop that preserves exact production-to-integration ancestry.
when-to-use:
- release loop, release cadence, release every N hours
- "set up a loop to release every 4-6 hours"
- When you want an unattended release drain under explicit live-mode arming
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

Run a recurring, velocity-gated integration-to-production release cut without rewriting either
branch. The loop may stop after opening the release PR or may fast-forward a previously reviewed
release PR when the operator explicitly arms that policy.

## Non-negotiable invariant

The production commit itself must be reachable from integration:

```bash
git fetch origin
git merge-base --is-ancestor "origin/$PROD" "origin/$INT"
```

Content parity, patch-id equality, and a clean merge are not substitutes for ancestry. A
cherry-pick, squash, rebase-merge, or content-fold commit creates a different SHA and leaves the
next cut structurally broken.

- `origin/$PROD` is an ancestor of `origin/$INT` ⇒ the release path may continue.
- `origin/$INT` is an ancestor of `origin/$PROD` ⇒ integration is behind-only; it may be moved to
  the exact production SHA by a plain fast-forward push.
- Neither is an ancestor ⇒ **DIVERGED: stop and report.** Never synthesize a release branch,
  content-fold PR, or automatic rebase-forward repair.

The `release` skill supplies the frozen-ref and fast-forward mechanics. This skill is stricter on
divergence: any generic cherry-pick, API rebase-merge, or rebase-forward fallback is forbidden.

## Why velocity-gated cadence

Tick often, but cut only when integration is at least five patch-unique commits ahead of
production, or at least four hours have elapsed and one patch-unique commit is waiting:

```bash
git fetch origin
N=$(git rev-list --count --right-only --cherry-pick "origin/$PROD...origin/$INT")
LAST=$(git log -1 --format=%ct "origin/$PROD")
AGE_H=$(( ($(date +%s) - LAST) / 3600 ))
# cut iff N >= 5 OR (AGE_H >= 4 AND N >= 1)
```

A fixed interval over-releases quiet periods and under-releases busy ones. A deferred tick is the
normal outcome.

## One cycle

Each firing runs these stages and stops at the first blocker.

### 1. Resolve branches and exact ancestry

Derive `$INT` and `$PROD` from the repo profile or deployment configuration; never infer production
from the GitHub default branch alone. Assert both refs exist and differ.

If production is already an ancestor of integration, continue. If integration is behind-only,
re-read the live-mode arm file adjacent to one exact fast-forward fold:

```bash
[ -f .claude/state/release-loop-live ] \
  || { echo "dry-run: WOULD fast-forward $INT to origin/$PROD"; exit 0; }
git push origin "origin/${PROD}:refs/heads/${INT}"
```

A rejection stops the cycle. Never add force. True two-sided divergence also stops the cycle and
requires an explicit operator-owned repair under a repository freeze.

### 2. Land one existing release PR first

One open `release/*` PR against production outranks cutting another. With zero, continue to the
cut gate. More than one is ambiguous: stop and report all of them. Any non-release PR against
production also stops the cycle.

Land only when all configured gates hold: not draft, no hold label, mergeable and clean, checks are
non-empty with at least one pass and every check pass/skipping, zero unresolved threads, and no
native skip-ci token on the frozen head.

Landing is a plain fast-forward push of the exact frozen SHA:

```bash
git fetch origin
CUT_SHA=$(gh pr view "$PR" --json headRefOid --jq .headRefOid)
git merge-base --is-ancestor "origin/$PROD" "$CUT_SHA" \
  || { echo "STOP: production moved; re-cut later"; exit 1; }
[ -f .claude/state/release-loop-live ] \
  || { echo "dry-run: WOULD land $CUT_SHA"; exit 0; }
git push origin "${CUT_SHA}:refs/heads/${PROD}"
```

Never use `gh pr merge`, a UI merge, `--force`, or an API rebase-merge fallback. Those mint new
production SHAs and break the invariant. A protected-branch rejection is a configuration blocker,
not permission to degrade the merge method.

### 3. Apply the velocity and linear-history gates

When no release PR is open, evaluate `N` and `AGE_H`. If the velocity gate passes, require no merge
commits in `origin/$PROD..origin/$INT` and re-run the exact ancestry check immediately before the
cut. Any failed or indeterminate read stops the cycle.

### 4. Cut one immutable snapshot and open its PR

Pick an unused `release/YYYY-MM-DD[-N]` name by exact remote-ref probing. Freeze the integration tip
and push that SHA directly; no checkout or worktree is needed:

```bash
CUT_SHA=$(git rev-parse "origin/$INT")
[ -f .claude/state/release-loop-live ] \
  || { echo "dry-run: WOULD cut $NAME at $CUT_SHA"; exit 0; }
git push origin "${CUT_SHA}:refs/heads/${NAME}"
```

Open the PR against production with a generated body file, report its URL, and stop. CI has not run
yet. Release branches are immutable: suffix a new name rather than moving an existing ref.

### 5. Fold post-release automation by exact SHA only

Semantic-release may append a version/changelog commit to production after the landing push. The
next cycle handles the behind-only case in stage 1 with an exact fast-forward. Repositories that
must allow integration commits during that window need an integration freeze or a release workflow
that performs the exact fold before unfreezing.

If integration advances first, the branches are two-sided divergent. Stop; never hide the failure
with a replacement content commit. This is the structural reason the fold and freeze are one
contract.

### 6. Report and finish

Every cycle records mode, spec version, velocity, action, and exact `CUT_SHA` when applicable. Report
`folded exact SHA`, `landed`, `cut`, `deferred`, or `blocked (<reason>)`. Complete the Atrium run and
return the repeat card to its home status only after the comment exists.

## Arming

Dry-run is the default. The operator alone creates `.claude/state/release-loop-live`; the loop never
creates it. Re-read the marker immediately before every push. Disarm while changing release policy,
when the deployed spec is stale or indeterminate, and whenever exact ancestry is broken.

Use a durable scheduler (Atrium repeat card, cron, or launchd) for unattended operation. The prompt
must be self-contained, name the repo and branches, run a freshness preflight, and encode the exact
ancestry stop condition. Leave an operator-visible note with cadence and the disarm control.
